"""Epic and issue creation handler."""

import json
import logging
import subprocess
import urllib.parse
from pathlib import Path
from typing import Any, Dict, List, Optional

try:
    import yaml
except ImportError as exc:
    raise ImportError("PyYAML is required. Install with: pip install PyYAML") from exc

from ..config import Config
from ..exceptions import PlatformError


logger = logging.getLogger(__name__)


class EpicIssueCreator:
    """Creates GitLab epics and issues using the glab CLI."""

    def __init__(
        self,
        config: Config,
        dry_run: bool = False
    ) -> None:
        """Initialize the creator.

        Args:
            config: Configuration object with defaults.
            dry_run: If True, only print commands without executing them.
        """
        self.config = config
        self.group = config.get_default_group()
        self.dry_run = dry_run
        self.created_issues: List[Dict[str, str]] = []
        self.issue_id_mapping: Dict[str, Dict[str, str]] = {}  # yaml_id -> {'iid': ..., 'url': ...}

    def _run_glab_command(self, cmd: List[str]) -> str:
        """Run a glab command and return its output.

        Args:
            cmd: List of command arguments to pass to glab.

        Returns:
            Command output as a string.

        Raises:
            PlatformError: If the command fails.
        """
        full_cmd = ['glab'] + cmd

        if self.dry_run:
            logger.info("[DRY RUN] Would execute: %s", ' '.join(full_cmd))
            return ""

        try:
            logger.debug("Executing: %s", ' '.join(full_cmd))
            result = subprocess.run(
                full_cmd,
                capture_output=True,
                text=True,
                check=True
            )
            return result.stdout.strip()
        except subprocess.CalledProcessError as err:
            error_msg = f"Command failed: {' '.join(full_cmd)}\n{err.stderr}"
            logger.error(error_msg)
            raise PlatformError(error_msg) from err
        except FileNotFoundError as err:
            error_msg = "glab command not found. Please install glab CLI."
            logger.error(error_msg)
            raise PlatformError(error_msg) from err

    def create_epic(self, epic_config: Dict[str, Any]) -> str:
        """Create a new epic or return existing epic ID.

        Args:
            epic_config: Dictionary containing epic configuration with either:
                         - 'id': existing epic ID
                         - 'title' and optionally 'description': for new epic
                         - 'labels': List of label names (merged with defaults)

        Returns:
            Epic ID as a string.

        Raises:
            PlatformError: If epic creation fails.
            ValueError: If epic_config is invalid.
        """
        if 'id' in epic_config:
            epic_id = str(epic_config['id'])
            logger.info("Using existing epic ID: %s", epic_id)
            return epic_id

        if 'title' not in epic_config:
            raise ValueError("Epic must have either 'id' or 'title' field")

        title = epic_config['title']
        description = epic_config.get('description', '')

        logger.info("Creating epic: %s", title)
        # Use GitLab API to create epic (glab epic create doesn't exist)
        # Endpoint: POST /groups/:id/epics
        if not self.group:
            raise ValueError(
                "Group path is required to create epics.\n"
                "Please set 'default_group' in your glab_config.yaml file."
            )

        # Merge default epic labels from config with epic-specific labels
        default_labels = self.config.get_default_epic_labels()
        epic_labels = epic_config.get('labels', [])

        # Combine and deduplicate labels
        all_labels = list(dict.fromkeys(default_labels + epic_labels))

        # Validate labels against allowed list (if configured)
        self._validate_issue_labels(all_labels)  # Reuse validation logic

        # URL encode the group path
        encoded_group = urllib.parse.quote(self.group, safe='')

        cmd = ['api', '-X', 'POST', f'groups/{encoded_group}/epics',
               '-f', f'title={title}']

        if description:
            cmd.extend(['-f', f'description={description}'])

        if all_labels:
            # GitLab API expects labels as comma-separated string
            labels_str = ','.join(all_labels)
            cmd.extend(['-f', f'labels={labels_str}'])

        output = self._run_glab_command(cmd)

        if self.dry_run:
            return "DRY_RUN_EPIC_ID"

        # Parse JSON response to get epic IID (not ID!)
        # The linking API requires the IID, not the global ID
        try:
            response = json.loads(output)
            epic_iid = str(response['iid'])
            epic_id = str(response['id'])
            logger.info("Created epic with ID: %s, IID: %s", epic_id, epic_iid)
            return epic_iid  # Return IID for linking
        except (json.JSONDecodeError, KeyError) as err:
            raise PlatformError(
                f"Failed to parse epic creation response: {err}\nOutput: {output}"
            ) from err

    def _extract_epic_id(self, output: str) -> str:
        """Extract epic ID from glab output.

        Args:
            output: Output from glab epic create command.

        Returns:
            Epic ID as a string.

        Raises:
            PlatformError: If epic ID cannot be extracted.
        """
        # Try to extract from URL format first
        if 'epics/' in output:
            parts = output.split('epics/')
            if len(parts) > 1:
                epic_id = parts[1].split()[0].strip()
                return epic_id

        # Try to extract from #ID format
        if '#' in output:
            parts = output.split('#')
            if len(parts) > 1:
                epic_id = parts[1].split()[0].strip()
                return epic_id

        raise PlatformError(f"Could not extract epic ID from output: {output}")

    def _validate_issue_description(self, issue_config: Dict[str, Any]) -> None:
        """Validate that issue description contains required sections.

        Args:
            issue_config: Dictionary containing issue configuration.

        Raises:
            ValueError: If required sections are missing from description.
        """
        required_sections = self.config.get_required_sections()
        if not required_sections:
            return

        description = issue_config.get('description', '')
        if not description:
            missing = ', '.join(required_sections)
            raise ValueError(
                f"Issue '{issue_config.get('title', 'unknown')}' has no description. "
                f"Required sections: {missing}"
            )

        missing_sections = []
        for section in required_sections:
            # Look for "# Section" or "## Section" patterns
            if f"# {section}" not in description:
                missing_sections.append(section)

        if missing_sections:
            missing = ', '.join(missing_sections)
            raise ValueError(
                f"Issue '{issue_config.get('title', 'unknown')}' missing required sections: {missing}"
            )

    def _validate_issue_labels(self, labels: List[str]) -> None:
        """Validate that issue labels are in the allowed list.

        Args:
            labels: List of label names to validate.

        Raises:
            ValueError: If any label is not in the allowed list.
        """
        allowed_labels = self.config.get_allowed_labels()
        if allowed_labels is None:
            # No validation configured
            return

        if not allowed_labels:
            # Empty allowed list means no labels are allowed
            if labels:
                raise ValueError(
                    f"Labels are not allowed (allowed_labels is empty), but found: {', '.join(labels)}"
                )
            return

        # Check each label
        unknown_labels = []
        for label in labels:
            if label not in allowed_labels:
                unknown_labels.append(label)

        if unknown_labels:
            raise ValueError(
                f"Unknown labels found: {', '.join(unknown_labels)}\n"
                f"Allowed labels are: {', '.join(allowed_labels)}"
            )

    def create_issue(
        self,
        issue_config: Dict[str, Any],
        epic_id: Optional[str] = None
    ) -> str:
        """Create a GitLab issue.

        Args:
            issue_config: Dictionary containing issue configuration:
                          - id: Optional YAML-local identifier for dependencies
                          - title: Issue title (required)
                          - description: Issue description
                          - labels: List of label names (merged with defaults)
                          - assignee: Assignee username
                          - milestone: Milestone title
                          - due_date: Due date in YYYY-MM-DD format
                          - dependencies: List of YAML IDs this issue depends on
            epic_id: Epic ID to add the issue to (optional).

        Returns:
            Issue ID/URL as a string.

        Raises:
            PlatformError: If issue creation fails.
            ValueError: If issue_config is invalid.
        """
        if 'title' not in issue_config:
            raise ValueError("Issue must have a 'title' field")

        # Validate required sections in description
        self._validate_issue_description(issue_config)

        title = issue_config['title']
        yaml_id = issue_config.get('id')
        id_suffix = f" (id: {yaml_id})" if yaml_id else ""
        logger.info("Creating issue: %s%s", title, id_suffix)

        cmd = ['issue', 'create', '--title', title]

        # Add optional fields
        if 'description' in issue_config:
            cmd.extend(['--description', issue_config['description']])

        # Merge default labels from config with issue-specific labels
        default_labels = self.config.get_default_labels()
        issue_labels = issue_config.get('labels', [])

        # Combine and deduplicate labels
        all_labels = list(dict.fromkeys(default_labels + issue_labels))

        # Validate labels against allowed list (if configured)
        self._validate_issue_labels(all_labels)

        if all_labels:
            labels = ','.join(all_labels)
            cmd.extend(['--label', labels])

        if 'assignee' in issue_config:
            cmd.extend(['--assignee', issue_config['assignee']])

        if 'milestone' in issue_config:
            cmd.extend(['--milestone', issue_config['milestone']])

        if 'due_date' in issue_config:
            # glab uses --due flag for due date
            cmd.extend(['--due', issue_config['due_date']])

        output = self._run_glab_command(cmd)

        if self.dry_run:
            issue_url = 'DRY_RUN_ISSUE_URL'
            issue_iid = 'DRY_RUN_IID'
            # Track the yaml_id mapping for dependency linking
            if yaml_id:
                self.issue_id_mapping[yaml_id] = {'url': issue_url, 'iid': issue_iid}
            # Still show the linking command in dry-run mode
            if epic_id:
                self._link_issue_to_epic(issue_url, epic_id)
            issue_info = {
                'title': title,
                'id': issue_url
            }
            self.created_issues.append(issue_info)
            return issue_url

        # Extract issue URL/ID from output
        issue_url = self._extract_issue_id(output)
        logger.info("Created issue: %s", issue_url)
        # Extract iid from the created issue for dependency tracking
        issue_iid = self._extract_issue_iid_from_url(issue_url)

        # Track the yaml_id mapping for dependency linking
        if yaml_id:
            self.issue_id_mapping[yaml_id] = {'url': issue_url, 'iid': issue_iid}
            logger.debug("Mapped YAML ID '%s' to issue #%s", yaml_id, issue_iid)
        # Link to epic if provided
        if epic_id:
            self._link_issue_to_epic(issue_url, epic_id)

        issue_info = {
            'title': title,
            'id': issue_url
        }
        self.created_issues.append(issue_info)
        return issue_url

    def _extract_issue_id(self, output: str) -> str:
        """Extract issue ID/URL from glab output.

        Args:
            output: Output from glab issue create command.

        Returns:
            Issue ID or URL as a string.

        Raises:
            PlatformError: If issue ID cannot be extracted.
        """
        # glab issue create typically returns the issue URL or #ID
        if output:
            # Return the full output which usually contains the issue reference
            return output.split()[0] if output else "unknown"

        raise PlatformError("Could not extract issue ID from output")

    def _extract_issue_iid_from_url(self, issue_url: str) -> str:
        """Extract issue iid from issue URL.

        Args:
            issue_url: Issue URL (e.g., https://gitlab.com/group/project/-/issues/123).

        Returns:
            Issue iid as a string.

        Raises:
            PlatformError: If iid cannot be extracted.
        """
        # URL format: https://gitlab.../group/project/-/issues/123
        if '/-/issues/' in issue_url:
            parts = issue_url.split('/-/issues/')
            if len(parts) == 2:
                iid = parts[1].split('/')[0].split('?')[0]
                return iid

        # Fallback: try to extract from #ID format
        if '#' in issue_url:
            return issue_url.split('#')[-1].split()[0]

        # If already a number, return it
        if issue_url.isdigit():
            return issue_url

        raise PlatformError(f"Could not extract iid from issue URL: {issue_url}")

    def _get_group_path(self) -> Optional[str]:
        """Get the group path for epic operations.

        Returns:
            Group path string, or None if not available.
        """
        return self.group

    def _get_global_issue_id(self, issue_id: str) -> Optional[str]:
        """Get the global issue ID from an issue URL or iid.

        The GitLab API for epic-issue linking requires the global issue ID,
        not the project-scoped iid.

        Args:
            issue_id: Issue URL or iid.

        Returns:
            Global issue ID as string, or None if not found.
        """
        # Extract project path and iid from URL
        # URL format: https://gitlab.../group/project/-/issues/123
        if '/-/issues/' in issue_id:
            parts = issue_id.split('/-/issues/')
            if len(parts) == 2:
                project_url = parts[0]
                iid = parts[1].split('/')[0].split('?')[0]

                # Extract project path from URL
                # Format: https://gitlab.example.com/group/subgroup/project
                if '//' in project_url:
                    project_path = '/'.join(project_url.split('//')[1].split('/')[1:])
                else:
                    project_path = project_url

                encoded_project = urllib.parse.quote(project_path, safe='')
                api_endpoint = f"projects/{encoded_project}/issues/{iid}"

                try:
                    output = self._run_glab_command(['api', api_endpoint])
                    if output:
                        data = json.loads(output)
                        return str(data.get('id'))
                except (PlatformError, json.JSONDecodeError) as err:
                    logger.warning("Failed to get global issue ID: %s", err)
                    return None

        return None

    def _link_issue_to_epic(self, issue_id: str, epic_id: str) -> None:
        """Link an issue to an epic using GitLab API.

        Uses the GitLab API endpoint:
        POST /groups/:id/epics/:epic_iid/issues/:issue_id

        Note: The API requires the global issue ID, not the project-scoped iid.

        Args:
            issue_id: Issue URL (preferred) or iid.
            epic_id: Epic ID (iid within the group).

        Raises:
            PlatformError: If linking fails.
        """
        logger.info("Linking issue %s to epic %s", issue_id, epic_id)
        group_path = self._get_group_path()
        if not group_path:
            logger.warning(
                "Cannot link issue to epic: group path not specified.\n"
                "Please set 'default_group' in your glab_config.yaml file."
            )
            return

        # Get the global issue ID (required by the API)
        global_issue_id = self._get_global_issue_id(issue_id)
        if not global_issue_id:
            # Fallback: try using the ID directly (might work if already global)
            if '#' in issue_id:
                global_issue_id = issue_id.split('#')[-1].split()[0]
            elif '/' in issue_id:
                global_issue_id = issue_id.rstrip('/').split('/')[-1]
            else:
                global_issue_id = issue_id
            logger.debug("Using issue ID directly: %s", global_issue_id)
        # URL-encode the group path for the API endpoint
        encoded_group = urllib.parse.quote(group_path, safe='')

        # Build the API endpoint
        api_endpoint = f"groups/{encoded_group}/epics/{epic_id}/issues/{global_issue_id}"

        cmd = ['api', '-X', 'POST', api_endpoint]

        try:
            self._run_glab_command(cmd)
            logger.info("Successfully linked issue to epic")
        except PlatformError as err:
            logger.warning("Failed to link issue to epic: %s", err)
            # Don't fail the whole operation if linking fails

    def _create_issue_dependency_link(
        self,
        blocking_issue_iid: str,
        blocked_issue_iid: str,
        project_id: str
    ) -> None:
        """Create a dependency link between two issues.

        Uses the GitLab API endpoint:
        POST /projects/:id/issues/:issue_iid/links
        with link_type=blocks

        Args:
            blocking_issue_iid: The iid of the issue that blocks.
            blocked_issue_iid: The iid of the issue that is blocked.
            project_id: The project ID (can be namespace/project or numeric ID).

        Raises:
            PlatformError: If linking fails.
        """
        logger.info(
            "Creating dependency: issue #%s blocks #%s",
            blocking_issue_iid, blocked_issue_iid
        )

        # URL-encode the project path
        encoded_project = urllib.parse.quote(project_id, safe='')

        # Build the API endpoint for the blocking issue
        api_endpoint = f"projects/{encoded_project}/issues/{blocking_issue_iid}/links"

        # The link_type=blocks means: blocking_issue blocks blocked_issue
        cmd = [
            'api',
            '-X', 'POST',
            api_endpoint,
            '-f', f'target_project_id={project_id}',
            '-f', f'target_issue_iid={blocked_issue_iid}',
            '-f', 'link_type=blocks'
        ]

        try:
            self._run_glab_command(cmd)
            logger.info("Successfully created dependency link")
        except PlatformError as err:
            logger.warning("Failed to create dependency link: %s", err)
            # Don't fail the whole operation if linking fails

    def process_yaml_file(self, yaml_path: Path) -> None:
        """Process a YAML file and create epic and issues.

        Args:
            yaml_path: Path to the YAML configuration file.

        Raises:
            PlatformError: If creation fails.
            ValueError: If YAML structure is invalid.
        """
        logger.info("Loading configuration from: %s", yaml_path)
        with open(yaml_path, 'r', encoding='utf-8') as yaml_file:
            config = yaml.safe_load(yaml_file)

        if not config:
            raise ValueError("YAML file is empty")

        if 'epic' not in config:
            raise ValueError("YAML must contain 'epic' section")

        if 'issues' not in config or not config['issues']:
            raise ValueError("YAML must contain 'issues' section with at least one issue")

        # Create or get epic
        epic_config = config['epic']
        epic_id = self.create_epic(epic_config)

        # Create issues
        issues = config['issues']
        logger.info("Creating %s issues...", len(issues))
        for idx, issue_config in enumerate(issues, 1):
            try:
                self.create_issue(issue_config, epic_id)
            except (PlatformError, ValueError) as err:
                logger.error("Failed to create issue %s: %s", idx, err)
                raise

        # Create dependency links after all issues are created
        if self.issue_id_mapping:
            self._create_dependency_links(issues)

        logger.info("Successfully completed all operations")

    def _create_dependency_links(self, issues: List[Dict[str, Any]]) -> None:
        """Create dependency links between issues based on YAML configuration.

        Args:
            issues: List of issue configurations from YAML.
        """
        logger.info("Creating dependency links...")

        # Get the project ID from the first created issue URL
        project_id = self._extract_project_id_from_url()
        if not project_id:
            logger.warning("Cannot create dependency links: unable to determine project ID")
            return

        dependency_count = 0
        for issue_config in issues:
            yaml_id = issue_config.get('id')
            dependencies = issue_config.get('dependencies', [])

            if not yaml_id or not dependencies:
                continue

            # Get the GitLab iid for this issue
            blocked_issue = self.issue_id_mapping.get(yaml_id)
            if not blocked_issue:
                logger.warning("Issue with YAML ID '%s' not found in mapping", yaml_id)
                continue

            blocked_iid = blocked_issue['iid']

            # Create links for each dependency
            for dep_yaml_id in dependencies:
                blocking_issue = self.issue_id_mapping.get(dep_yaml_id)
                if not blocking_issue:
                    logger.warning(
                        "Dependency '%s' for issue '%s' not found in mapping",
                        dep_yaml_id, yaml_id
                    )
                    continue

                blocking_iid = blocking_issue['iid']

                try:
                    self._create_issue_dependency_link(
                        blocking_iid,
                        blocked_iid,
                        project_id
                    )
                    dependency_count += 1
                except PlatformError as err:
                    logger.warning(
                        "Failed to create dependency link from '%s' to '%s': %s",
                        dep_yaml_id, yaml_id, err
                    )

        logger.info("Created %s dependency links", dependency_count)

    def _extract_project_id_from_url(self) -> Optional[str]:
        """Extract project ID from the first created issue URL.

        Returns:
            Project path (namespace/project) or None if unable to extract.
        """
        if not self.created_issues:
            return None

        first_issue_url = self.created_issues[0]['id']

        # Handle dry-run mode
        if first_issue_url == 'DRY_RUN_ISSUE_URL':
            # Use the group path if available as project path for dry-run
            if self.group:
                # Use generic project name for dry-run demonstration
                return f"{self.group}/project"
            return "DRY_RUN_PROJECT_ID"

        # URL format: https://gitlab.com/group/subgroup/project/-/issues/123
        if '/-/issues/' in first_issue_url:
            parts = first_issue_url.split('/-/issues/')
            if len(parts) == 2:
                project_url = parts[0]
                # Extract project path from URL
                if '//' in project_url:
                    project_path = '/'.join(project_url.split('//')[1].split('/')[1:])
                    return project_path

        return None

    def print_summary(self) -> None:
        """Print a summary of created issues."""
        if not self.created_issues:
            logger.info("No issues were created")
            return

        print("\n" + "=" * 60)
        print("SUMMARY: Created Issues")
        print("=" * 60)
        for issue in self.created_issues:
            print(f"  - {issue['title']}")
            print(f"    ID: {issue['id']}")
        print("=" * 60)
        print(f"Total: {len(self.created_issues)} issues created")

        if self.issue_id_mapping:
            print(f"Total: {len(self.issue_id_mapping)} issues with IDs tracked for dependencies")

        print()
