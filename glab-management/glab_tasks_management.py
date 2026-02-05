#!/usr/bin/env python3
"""GitLab Epic and Issue management tool using the glab CLI.

LEGACY VERSION: This is the original working version kept for safety while
the new modular version (ci_platform_manager) is being tested. This file
will be replaced with a deprecation wrapper once the new version is fully
verified and tested in production.

This script provides commands to:
- Create issues from YAML definitions and link them to epics
- Load ticket (issue) information and related epic from GitLab (markdown output)
- Load epic information with all associated issues (markdown output)
- Load milestone information with all associated issues and epics (markdown output)
- Load merge request (MR) information from GitLab (markdown output)
- Search for issues, epics, and milestones by text query (text output)
- Post review comments from YAML files to merge requests
- Create merge requests from current branch

Example:
    # Create issues from YAML
    $ python glab_tasks_management.py create epic_definition.yaml
    $ python glab_tasks_management.py create --dry-run epic_definition.yaml

    # Load ticket information (includes dependencies, outputs markdown)
    $ python glab_tasks_management.py load 113
    $ python glab_tasks_management.py load https://gitlab.example.com/group/project/-/issues/113

    # Load epic information (includes all issues in the epic, outputs markdown)
    $ python glab_tasks_management.py load &21
    $ python glab_tasks_management.py load https://gitlab.example.com/groups/mygroup/-/epics/21
    $ python glab_tasks_management.py load 21 --type epic

    # Load milestone information (includes all issues and epics, outputs markdown)
    $ python glab_tasks_management.py load %123
    $ python glab_tasks_management.py load https://gitlab.example.com/group/project/-/milestones/123
    $ python glab_tasks_management.py load 123 --type milestone

    # Load merge request information (outputs markdown)
    $ python glab_tasks_management.py load !134
    $ python glab_tasks_management.py load 134 --type mr
    $ python glab_tasks_management.py load https://gitlab.example.com/group/project/-/merge_requests/134

    # Search issues, epics, and milestones (outputs text)
    $ python glab_tasks_management.py search issues "streaming"
    $ python glab_tasks_management.py search epics "video"
    $ python glab_tasks_management.py search milestones "v1.0" --state active
    $ python glab_tasks_management.py search issues "SRT" --state opened --limit 10

    # Post review comment from YAML to merge request
    $ python glab_tasks_management.py comment planning/reviews/MR134-review.yaml
    $ python glab_tasks_management.py comment planning/reviews/MR134-review.yaml --mr 134

    # Create merge request
    $ python glab_tasks_management.py create-mr --title "Add feature" --draft
    $ python glab_tasks_management.py create-mr --fill --reviewer alice
"""

import argparse
import json
import logging
import subprocess
import sys
import urllib.parse
from pathlib import Path
from typing import Any, Dict, List, Optional

try:
    import yaml
except ImportError:
    print("Error: PyYAML is required. Install with: pip install PyYAML")
    sys.exit(1)


logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class Config:
    """Configuration management for the GitLab epic/issue tool.

    Loads configuration from a YAML file and provides access to settings.
    Configuration can be overridden by command-line arguments.

    Config file resolution:
    1. If --config is specified: use that path (fail if not found)
    2. Otherwise: use ./glab_config.yaml in current working directory (fail if not found)

    Note: glab_config.example.yaml serves as documentation/template only, not a runtime fallback.
    """

    def __init__(self, config_path: Optional[Path] = None) -> None:
        """Initialize configuration.

        Args:
            config_path: Path to config file. If None, uses ./glab_config.yaml
                        in current working directory.

        Raises:
            FileNotFoundError: If config file doesn't exist at the specified or default path.
        """
        self.config_data: Dict[str, Any] = {}
        self.loaded_config_path: Optional[Path] = None

        if config_path is not None:
            # Explicit config path specified via --config
            if not config_path.exists():
                script_dir = Path(__file__).parent
                example_config = script_dir / "glab_config.example.yaml"
                raise FileNotFoundError(
                    f"Config file not found: {config_path}\n\n"
                    f"To fix this:\n"
                    f"  - Verify the path specified with --config is correct\n"
                    f"  - OR copy the example config to your desired location:\n"
                    f"    cp {example_config} {config_path}"
                )
            self._load_config_file(config_path)
        else:
            # Use default location: ./glab_config.yaml in current directory
            cwd_config = Path.cwd() / "glab_config.yaml"
            if not cwd_config.exists():
                script_dir = Path(__file__).parent
                example_config = script_dir / "glab_config.example.yaml"
                raise FileNotFoundError(
                    f"Config file not found: {cwd_config}\n\n"
                    f"To fix this:\n"
                    f"  - Copy the example config to your project directory:\n"
                    f"    cp {example_config} {cwd_config}\n"
                    f"  - OR specify a custom config path:\n"
                    f"    --config /path/to/your/config.yaml"
                )
            self._load_config_file(cwd_config)

    def _load_config_file(self, config_path: Path) -> None:
        """Load configuration from a file.

        Args:
            config_path: Path to the configuration file.

        Raises:
            yaml.YAMLError: If YAML parsing fails.
            IOError: If file cannot be read.
        """
        with open(config_path, 'r') as f:
            self.config_data = yaml.safe_load(f) or {}
        self.loaded_config_path = config_path
        logger.info(f"Loaded configuration from: {config_path}")

    def get_default_group(self) -> Optional[str]:
        """Get the default GitLab group path for epic operations.

        Returns:
            Default group path or None.
        """
        return self.config_data.get('gitlab', {}).get('default_group')

    def get_default_labels(self) -> List[str]:
        """Get the default labels to apply to issues.

        Returns:
            List of default label names.
        """
        return self.config_data.get('labels', {}).get('default', [])

    def get_default_epic_labels(self) -> List[str]:
        """Get the default labels to apply to epics.

        Returns:
            List of default epic label names.
        """
        return self.config_data.get('labels', {}).get('default_epic', [])

    def get_allowed_labels(self) -> Optional[List[str]]:
        """Get the allowed labels list for validation.

        Returns:
            List of allowed label names, or None if not configured.
        """
        allowed = self.config_data.get('labels', {}).get('allowed_labels', [])
        return allowed if allowed else None

    def get_required_sections(self) -> List[str]:
        """Get required sections for issue descriptions.

        Returns:
            List of required section names.
        """
        sections = self.config_data.get('issue_template', {}).get('sections', [])
        return [s['name'] for s in sections if s.get('required', False)]


class GlabError(Exception):
    """Exception raised for glab command failures."""
    pass


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
            GlabError: If the command fails.
        """
        full_cmd = ['glab'] + cmd

        if self.dry_run:
            logger.info(f"[DRY RUN] Would execute: {' '.join(full_cmd)}")
            return ""

        try:
            logger.debug(f"Executing: {' '.join(full_cmd)}")
            result = subprocess.run(
                full_cmd,
                capture_output=True,
                text=True,
                check=True
            )
            return result.stdout.strip()
        except subprocess.CalledProcessError as e:
            error_msg = f"Command failed: {' '.join(full_cmd)}\n{e.stderr}"
            logger.error(error_msg)
            raise GlabError(error_msg) from e
        except FileNotFoundError:
            error_msg = "glab command not found. Please install glab CLI."
            logger.error(error_msg)
            raise GlabError(error_msg)

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
            GlabError: If epic creation fails.
            ValueError: If epic_config is invalid.
        """
        if 'id' in epic_config:
            epic_id = str(epic_config['id'])
            logger.info(f"Using existing epic ID: {epic_id}")
            return epic_id

        if 'title' not in epic_config:
            raise ValueError("Epic must have either 'id' or 'title' field")

        title = epic_config['title']
        description = epic_config.get('description', '')

        logger.info(f"Creating epic: {title}")

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
            logger.info(f"Created epic with ID: {epic_id}, IID: {epic_iid}")
            return epic_iid  # Return IID for linking
        except (json.JSONDecodeError, KeyError) as e:
            raise GlabError(f"Failed to parse epic creation response: {e}\nOutput: {output}")

    def _extract_epic_id(self, output: str) -> str:
        """Extract epic ID from glab output.

        Args:
            output: Output from glab epic create command.

        Returns:
            Epic ID as a string.

        Raises:
            GlabError: If epic ID cannot be extracted.
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

        raise GlabError(f"Could not extract epic ID from output: {output}")

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
            GlabError: If issue creation fails.
            ValueError: If issue_config is invalid.
        """
        if 'title' not in issue_config:
            raise ValueError("Issue must have a 'title' field")

        # Validate required sections in description
        self._validate_issue_description(issue_config)

        title = issue_config['title']
        yaml_id = issue_config.get('id')
        logger.info(f"Creating issue: {title}" + (f" (id: {yaml_id})" if yaml_id else ""))

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
        logger.info(f"Created issue: {issue_url}")

        # Extract iid from the created issue for dependency tracking
        issue_iid = self._extract_issue_iid_from_url(issue_url)

        # Track the yaml_id mapping for dependency linking
        if yaml_id:
            self.issue_id_mapping[yaml_id] = {'url': issue_url, 'iid': issue_iid}
            logger.debug(f"Mapped YAML ID '{yaml_id}' to issue #{issue_iid}")

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
            GlabError: If issue ID cannot be extracted.
        """
        # glab issue create typically returns the issue URL or #ID
        if output:
            # Return the full output which usually contains the issue reference
            return output.split()[0] if output else "unknown"

        raise GlabError("Could not extract issue ID from output")

    def _extract_issue_iid_from_url(self, issue_url: str) -> str:
        """Extract issue iid from issue URL.

        Args:
            issue_url: Issue URL (e.g., https://gitlab.com/group/project/-/issues/123).

        Returns:
            Issue iid as a string.

        Raises:
            GlabError: If iid cannot be extracted.
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

        raise GlabError(f"Could not extract iid from issue URL: {issue_url}")

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
                except (GlabError, json.JSONDecodeError) as e:
                    logger.warning(f"Failed to get global issue ID: {e}")
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
            GlabError: If linking fails.
        """
        logger.info(f"Linking issue {issue_id} to epic {epic_id}")

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
            logger.debug(f"Using issue ID directly: {global_issue_id}")

        # URL-encode the group path for the API endpoint
        encoded_group = urllib.parse.quote(group_path, safe='')

        # Build the API endpoint
        api_endpoint = f"groups/{encoded_group}/epics/{epic_id}/issues/{global_issue_id}"

        cmd = ['api', '-X', 'POST', api_endpoint]

        try:
            self._run_glab_command(cmd)
            logger.info("Successfully linked issue to epic")
        except GlabError as e:
            logger.warning(f"Failed to link issue to epic: {e}")
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
            GlabError: If linking fails.
        """
        logger.info(
            f"Creating dependency: issue #{blocking_issue_iid} blocks #{blocked_issue_iid}"
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
        except GlabError as e:
            logger.warning(f"Failed to create dependency link: {e}")
            # Don't fail the whole operation if linking fails

    def process_yaml_file(self, yaml_path: Path) -> None:
        """Process a YAML file and create epic and issues.

        Args:
            yaml_path: Path to the YAML configuration file.

        Raises:
            GlabError: If creation fails.
            ValueError: If YAML structure is invalid.
        """
        logger.info(f"Loading configuration from: {yaml_path}")

        with open(yaml_path, 'r') as f:
            config = yaml.safe_load(f)

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
        logger.info(f"Creating {len(issues)} issues...")

        for idx, issue_config in enumerate(issues, 1):
            try:
                self.create_issue(issue_config, epic_id)
            except (GlabError, ValueError) as e:
                logger.error(f"Failed to create issue {idx}: {e}")
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
                logger.warning(f"Issue with YAML ID '{yaml_id}' not found in mapping")
                continue

            blocked_iid = blocked_issue['iid']

            # Create links for each dependency
            for dep_yaml_id in dependencies:
                blocking_issue = self.issue_id_mapping.get(dep_yaml_id)
                if not blocking_issue:
                    logger.warning(
                        f"Dependency '{dep_yaml_id}' for issue '{yaml_id}' not found in mapping"
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
                except GlabError as e:
                    logger.warning(
                        f"Failed to create dependency link from '{dep_yaml_id}' "
                        f"to '{yaml_id}': {e}"
                    )

        logger.info(f"Created {dependency_count} dependency links")

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


class TicketLoader:
    """Loads GitLab issue and epic information using the glab CLI."""

    def __init__(self, config: Config) -> None:
        """Initialize the loader.

        Args:
            config: Configuration object with defaults.
        """
        self.config = config

    def _run_glab_command(self, cmd: List[str]) -> str:
        """Run a glab command and return its output.

        Args:
            cmd: List of command arguments to pass to glab.

        Returns:
            Command output as a string.

        Raises:
            GlabError: If the command fails.
        """
        full_cmd = ['glab'] + cmd

        try:
            logger.debug(f"Executing: {' '.join(full_cmd)}")
            result = subprocess.run(
                full_cmd,
                capture_output=True,
                text=True,
                check=True
            )
            return result.stdout.strip()
        except subprocess.CalledProcessError as e:
            error_msg = f"Command failed: {' '.join(full_cmd)}\n{e.stderr}"
            logger.error(error_msg)
            raise GlabError(error_msg) from e
        except FileNotFoundError:
            error_msg = "glab command not found. Please install glab CLI."
            logger.error(error_msg)
            raise GlabError(error_msg)

    def _parse_issue_reference(self, issue_ref: str) -> tuple:
        """Parse issue reference to extract project path and iid.

        Args:
            issue_ref: Issue reference (number, URL, or #number format).

        Returns:
            Tuple of (project_path, iid). project_path may be None if not in URL.
        """
        # URL format: https://gitlab.../group/project/-/issues/123
        if '/-/issues/' in issue_ref:
            parts = issue_ref.split('/-/issues/')
            if len(parts) == 2:
                project_url = parts[0]
                iid = parts[1].split('/')[0].split('?')[0]

                # Extract project path from URL
                if '//' in project_url:
                    project_path = '/'.join(project_url.split('//')[1].split('/')[1:])
                else:
                    project_path = project_url

                return (project_path, iid)

        # #123 format
        if issue_ref.startswith('#'):
            return (None, issue_ref[1:])

        # Plain number
        if issue_ref.isdigit():
            return (None, issue_ref)

        raise ValueError(f"Cannot parse issue reference: {issue_ref}")

    def _parse_epic_reference(self, epic_ref: str) -> tuple:
        """Parse epic reference to extract group path and iid.

        Args:
            epic_ref: Epic reference (number, URL, or &number format).

        Returns:
            Tuple of (group_path, iid). group_path may be None if not in URL.

        Raises:
            ValueError: If epic reference cannot be parsed.
        """
        # URL format: https://gitlab.../groups/mygroup/-/epics/21
        if '/-/epics/' in epic_ref:
            parts = epic_ref.split('/-/epics/')
            if len(parts) == 2:
                group_url = parts[0]
                iid = parts[1].split('/')[0].split('?')[0]

                # Extract group path from URL
                # Format: https://gitlab.example.com/groups/mygroup
                if '/groups/' in group_url:
                    group_path = group_url.split('/groups/')[-1]
                elif '//' in group_url:
                    # Fallback: take everything after the domain
                    group_path = '/'.join(group_url.split('//')[1].split('/')[1:])
                else:
                    group_path = group_url

                return (group_path, iid)

        # &21 format (GitLab epic reference)
        if epic_ref.startswith('&'):
            return (None, epic_ref[1:])

        # Plain number
        if epic_ref.isdigit():
            return (None, epic_ref)

        raise ValueError(f"Cannot parse epic reference: {epic_ref}")

    def _parse_milestone_reference(self, milestone_ref: str) -> tuple:
        """Parse milestone reference to extract project/group path, iid, and milestone type.

        Args:
            milestone_ref: Milestone reference (number, URL, or %number format).

        Returns:
            Tuple of (project_or_group_path, iid, is_group_milestone).
            project_or_group_path may be None if not in URL.

        Raises:
            ValueError: If milestone reference cannot be parsed.
        """
        # URL format for group milestone: https://gitlab.../groups/mygroup/-/milestones/123
        if '/groups/' in milestone_ref and '/-/milestones/' in milestone_ref:
            parts = milestone_ref.split('/-/milestones/')
            if len(parts) == 2:
                group_url = parts[0]
                iid = parts[1].split('/')[0].split('?')[0]

                # Extract group path from URL
                # Format: https://gitlab.example.com/groups/mygroup/subgroup
                if '/groups/' in group_url:
                    group_path = group_url.split('/groups/')[-1]
                elif '//' in group_url:
                    # Fallback: take everything after the domain
                    group_path = '/'.join(group_url.split('//')[1].split('/')[1:])
                else:
                    group_path = group_url

                return (group_path, iid, True)

        # URL format for project milestone: https://gitlab.../group/project/-/milestones/123
        if '/-/milestones/' in milestone_ref:
            parts = milestone_ref.split('/-/milestones/')
            if len(parts) == 2:
                project_url = parts[0]
                iid = parts[1].split('/')[0].split('?')[0]

                # Extract project path from URL
                if '//' in project_url:
                    project_path = '/'.join(project_url.split('//')[1].split('/')[1:])
                else:
                    project_path = project_url

                return (project_path, iid, False)

        # %123 format (GitLab milestone reference)
        if milestone_ref.startswith('%'):
            return (None, milestone_ref[1:], None)

        # Plain number
        if milestone_ref.isdigit():
            return (None, milestone_ref, None)

        raise ValueError(f"Cannot parse milestone reference: {milestone_ref}")

    def load_issue(self, issue_ref: str) -> Dict[str, Any]:
        """Load issue information from GitLab.

        Args:
            issue_ref: Issue reference (number, URL, or #number format).

        Returns:
            Dictionary containing issue data.

        Raises:
            GlabError: If loading fails.
        """
        project_path, iid = self._parse_issue_reference(issue_ref)

        if project_path:
            encoded_project = urllib.parse.quote(project_path, safe='')
        else:
            # Use current repo via glab's :fullpath shorthand
            encoded_project = ":fullpath"

        api_endpoint = f"projects/{encoded_project}/issues/{iid}"

        output = self._run_glab_command(['api', api_endpoint])
        return json.loads(output)

    def load_epic(self, group_path: str, epic_iid: int) -> Dict[str, Any]:
        """Load epic information from GitLab.

        Args:
            group_path: GitLab group path.
            epic_iid: Epic iid within the group.

        Returns:
            Dictionary containing epic data.

        Raises:
            GlabError: If loading fails.
        """
        encoded_group = urllib.parse.quote(group_path, safe='')
        api_endpoint = f"groups/{encoded_group}/epics/{epic_iid}"

        output = self._run_glab_command(['api', api_endpoint])
        return json.loads(output)

    def _get_group_milestone_id(self, group_path: str, milestone_iid: str) -> Optional[str]:
        """Convert group milestone iid to id.

        Group milestone API requires id, not iid.
        List all milestones and find the one matching the iid.

        Args:
            group_path: GitLab group path.
            milestone_iid: Milestone iid within the group.

        Returns:
            Milestone id as string, or None if not found.

        Raises:
            GlabError: If API call fails.
        """
        encoded_group = urllib.parse.quote(group_path, safe='')
        api_endpoint = f"groups/{encoded_group}/milestones?per_page=100"

        try:
            output = self._run_glab_command(['api', api_endpoint])
            milestones = json.loads(output) if output else []

            for ms in milestones:
                if str(ms.get('iid')) == str(milestone_iid):
                    return str(ms.get('id'))

            return None
        except (GlabError, json.JSONDecodeError) as e:
            logger.warning(f"Failed to resolve milestone iid to id: {e}")
            return None

    def load_epic_issues(self, group_path: str, epic_iid: int) -> List[Dict[str, Any]]:
        """Load all issues associated with an epic.

        Args:
            group_path: GitLab group path.
            epic_iid: Epic iid within the group.

        Returns:
            List of issue dictionaries.

        Raises:
            GlabError: If loading fails.
        """
        encoded_group = urllib.parse.quote(group_path, safe='')
        api_endpoint = f"groups/{encoded_group}/epics/{epic_iid}/issues?per_page=100"

        try:
            output = self._run_glab_command(['api', api_endpoint])
            if not output:
                return []
            return json.loads(output)
        except GlabError as e:
            logger.warning(f"Failed to load epic issues: {e}")
            return []

    def load_epic_with_issues(self, epic_ref: str) -> Dict[str, Any]:
        """Load epic and all its associated issues.

        Args:
            epic_ref: Epic reference (number, URL, or &number format).

        Returns:
            Dictionary containing epic and issues data with structure:
            {
                'epic': {epic data},
                'issues': [list of issues]
            }

        Raises:
            GlabError: If loading fails.
            ValueError: If group path cannot be determined.
        """
        # Parse epic reference
        parsed_group, epic_iid = self._parse_epic_reference(epic_ref)

        # Determine group path
        final_group_path = parsed_group or self.config.get_default_group()

        if not final_group_path:
            raise ValueError(
                "Group path is required to load epic.\n"
                "Either include the group in the URL or set 'default_group' in your glab_config.yaml file."
            )

        # Load epic data
        epic_data = self.load_epic(final_group_path, int(epic_iid))

        # Load epic issues
        issues = self.load_epic_issues(final_group_path, int(epic_iid))

        return {
            'epic': epic_data,
            'issues': issues
        }

    def load_milestone_with_issues(self, milestone_ref: str) -> Dict[str, Any]:
        """Load milestone and all its associated issues.

        Args:
            milestone_ref: Milestone reference (number, URL, or %number format).

        Returns:
            Dictionary containing milestone, issues, and epic mapping with structure:
            {
                'milestone': {milestone data},
                'issues': [list of issues],
                'epic_map': {epic_iid: epic_data}
            }

        Raises:
            GlabError: If loading fails.
        """
        # Parse milestone reference
        parsed_path, milestone_iid, is_group_milestone = self._parse_milestone_reference(milestone_ref)

        # Determine if this is a group or project milestone
        if is_group_milestone is None:
            # Not determined from URL, use config default
            default_group = self.config.get_default_group()
            is_group_milestone = bool(default_group)
            if is_group_milestone:
                parsed_path = default_group

        if is_group_milestone:
            # Use group milestone API
            if parsed_path:
                encoded_path = urllib.parse.quote(parsed_path, safe='')
            else:
                # Should not happen if is_group_milestone is True
                raise ValueError(
                    "Group path is required for group milestone.\n"
                    "Either include the group in the URL or set 'default_group' in your glab_config.yaml file."
                )

            # Convert iid to id for group milestones (API requires id, not iid)
            milestone_id = self._get_group_milestone_id(parsed_path, milestone_iid)
            if not milestone_id:
                raise GlabError(f"Milestone iid {milestone_iid} not found in group {parsed_path}")

            api_endpoint = f"groups/{encoded_path}/milestones/{milestone_id}"
            issues_endpoint = f"groups/{encoded_path}/milestones/{milestone_id}/issues?per_page=100"
        else:
            # Use project milestone API
            if parsed_path:
                encoded_path = urllib.parse.quote(parsed_path, safe='')
            else:
                # Use current repo via glab's :fullpath shorthand
                encoded_path = ":fullpath"
            api_endpoint = f"projects/{encoded_path}/milestones/{milestone_iid}"
            issues_endpoint = f"projects/{encoded_path}/milestones/{milestone_iid}/issues?per_page=100"

        # Load milestone data
        output = self._run_glab_command(['api', api_endpoint])
        milestone_data = json.loads(output)

        # Load milestone issues
        try:
            issues_output = self._run_glab_command(['api', issues_endpoint])
            issues = json.loads(issues_output) if issues_output else []
        except GlabError as e:
            logger.warning(f"Failed to load milestone issues: {e}")
            issues = []

        # Load epic information for each issue
        epic_map = {}
        for issue in issues:
            epic_iid = issue.get('epic_iid')
            if epic_iid and epic_iid not in epic_map:
                # Extract group path from issue's project
                project_path = issue.get('references', {}).get('full', '').split('#')[0]
                if project_path:
                    group_path = '/'.join(project_path.split('/')[:-1])
                    if group_path:
                        try:
                            epic_data = self.load_epic(group_path, epic_iid)
                            epic_map[epic_iid] = epic_data
                        except GlabError as e:
                            logger.warning(f"Failed to load epic {epic_iid}: {e}")

        return {
            'milestone': milestone_data,
            'issues': issues,
            'epic_map': epic_map
        }

    def load_issue_links(self, project_path: str, issue_iid: str) -> Dict[str, List[Dict]]:
        """Load issue dependency links (blocking and blocked relationships).

        Args:
            project_path: GitLab project path.
            issue_iid: Issue iid within the project.

        Returns:
            Dictionary with 'blocking' and 'blocked' lists.

        Raises:
            GlabError: If loading fails.
        """
        encoded_project = urllib.parse.quote(project_path, safe='')
        api_endpoint = f"projects/{encoded_project}/issues/{issue_iid}/links"

        try:
            output = self._run_glab_command(['api', api_endpoint])
            if not output:
                return {'blocking': [], 'blocked': []}

            links = json.loads(output)

            # Separate into blocking (this issue blocks others) and blocked (this issue is blocked by others)
            blocking = []
            blocked_by = []

            for link in links:
                link_type = link.get('link_type')
                if link_type == 'blocks':
                    # This issue blocks the linked issue
                    blocking.append(link)
                elif link_type == 'is_blocked_by':
                    # This issue is blocked by the linked issue
                    blocked_by.append(link)

            return {'blocking': blocking, 'blocked_by': blocked_by}
        except GlabError as e:
            logger.warning(f"Failed to load issue links: {e}")
            return {'blocking': [], 'blocked_by': []}

    def load_ticket_with_epic(self, issue_ref: str) -> Dict[str, Any]:
        """Load issue and its related epic information.

        Args:
            issue_ref: Issue reference (number, URL, or #number format).

        Returns:
            Dictionary containing issue and epic data.

        Raises:
            GlabError: If loading fails.
        """
        issue_data = self.load_issue(issue_ref)

        result = {
            'issue': issue_data,
            'epic': None,
            'links': {'blocking': [], 'blocked_by': []}
        }

        # Check if issue has an associated epic
        epic_iid = issue_data.get('epic_iid')
        if epic_iid:
            # Extract group path from issue's project
            # The epic belongs to the parent group of the project
            project_path = issue_data.get('references', {}).get('full', '')
            if project_path:
                # Remove issue reference part and project name to get group
                # Format: group/subgroup/project#123
                project_full = project_path.split('#')[0]
                group_path = '/'.join(project_full.split('/')[:-1])

                if group_path:
                    try:
                        epic_data = self.load_epic(group_path, epic_iid)
                        result['epic'] = epic_data
                    except GlabError as e:
                        logger.warning(f"Failed to load epic {epic_iid}: {e}")

        # Load issue dependency links
        project_path = issue_data.get('references', {}).get('full', '').split('#')[0]
        if project_path:
            issue_iid = issue_data.get('iid')
            result['links'] = self.load_issue_links(project_path, str(issue_iid))

        return result

    def print_ticket_info(self, data: Dict[str, Any]) -> None:
        """Print ticket information in markdown format.

        Args:
            data: Dictionary containing issue and epic data.
        """
        issue = data['issue']
        epic = data.get('epic')
        links = data.get('links')
        self._print_markdown(issue, epic, links)

    def _print_markdown(self, issue: Dict[str, Any], epic: Optional[Dict[str, Any]], links: Optional[Dict[str, List[Dict]]] = None) -> None:
        """Print ticket info in markdown format."""
        print(f"# Issue #{issue.get('iid')}: {issue.get('title')}\n")

        print(f"**URL:** {issue.get('web_url')}  ")
        print(f"**State:** {issue.get('state')}  ")
        print(f"**Author:** {issue.get('author', {}).get('name', 'Unknown')}  ")

        labels = issue.get('labels', [])
        if labels:
            print(f"**Labels:** {', '.join([f'`{l}`' for l in labels])}  ")

        assignees = issue.get('assignees', [])
        if assignees:
            names = [a.get('name', a.get('username')) for a in assignees]
            print(f"**Assignees:** {', '.join(names)}  ")

        if issue.get('milestone'):
            print(f"**Milestone:** {issue['milestone'].get('title')}  ")

        if issue.get('due_date'):
            print(f"**Due Date:** {issue['due_date']}  ")

        print(f"\n**Created:** {issue.get('created_at')}  ")
        print(f"**Updated:** {issue.get('updated_at')}  ")

        # Print dependencies
        if links:
            blocked_by = links.get('blocked_by', [])
            blocking = links.get('blocking', [])

            if blocked_by:
                print("\n### ⛔ Blocked By\n")
                for link in blocked_by:
                    link_iid = link.get('iid')
                    link_title = link.get('title', 'Untitled')
                    link_state = link.get('state', 'unknown')
                    link_url = link.get('web_url', '')
                    print(f"- [#{link_iid} {link_title}]({link_url}) `[{link_state}]`")

            if blocking:
                print("\n### 🚧 Blocking\n")
                for link in blocking:
                    link_iid = link.get('iid')
                    link_title = link.get('title', 'Untitled')
                    link_state = link.get('state', 'unknown')
                    link_url = link.get('web_url', '')
                    print(f"- [#{link_iid} {link_title}]({link_url}) `[{link_state}]`")

        if epic:
            print(f"\n## Epic &{epic.get('iid')}: {epic.get('title')}\n")
            print(f"**URL:** {epic.get('web_url')}  ")
            print(f"**State:** {epic.get('state')}  ")

        print("\n## Description\n")
        description = issue.get('description', 'No description')
        print(description if description else '*No description*')
        print()

    def print_epic_info(self, data: Dict[str, Any]) -> None:
        """Print epic information in markdown format.

        Args:
            data: Dictionary containing epic and issues data.
        """
        epic = data['epic']
        issues = data.get('issues', [])
        self._print_epic_markdown(epic, issues)

    def _print_epic_markdown(self, epic: Dict[str, Any], issues: List[Dict[str, Any]]) -> None:
        """Print epic info in markdown format."""
        print(f"# Epic &{epic.get('iid')}: {epic.get('title')}\n")

        print(f"**URL:** {epic.get('web_url')}  ")
        print(f"**State:** {epic.get('state')}  ")
        print(f"**Author:** {epic.get('author', {}).get('name', 'Unknown')}  ")

        labels = epic.get('labels', [])
        if labels:
            label_names = [l.get('name', l) if isinstance(l, dict) else l for l in labels]
            print(f"**Labels:** {', '.join([f'`{l}`' for l in label_names])}  ")

        if epic.get('start_date'):
            print(f"**Start Date:** {epic['start_date']}  ")

        if epic.get('due_date'):
            print(f"**Due Date:** {epic['due_date']}  ")

        print(f"\n**Created:** {epic.get('created_at')}  ")
        print(f"**Updated:** {epic.get('updated_at')}  ")

        # Print issues in the epic
        print(f"\n## Issues in Epic ({len(issues)})\n")

        if not issues:
            print("*No issues in this epic*\n")
        else:
            # Group issues by state
            opened_issues = [i for i in issues if i.get('state') == 'opened']
            closed_issues = [i for i in issues if i.get('state') == 'closed']

            if opened_issues:
                print(f"### Opened ({len(opened_issues)})\n")
                for issue in opened_issues:
                    iid = issue.get('iid')
                    title = issue.get('title', 'Untitled')
                    url = issue.get('web_url', '')
                    issue_labels = issue.get('labels', [])
                    label_str = ', '.join([f'`{l}`' for l in issue_labels[:3]]) if issue_labels else '*none*'
                    if len(issue_labels) > 3:
                        label_str += f' *+{len(issue_labels) - 3} more*'
                    print(f"- [#{iid} {title}]({url})")
                    print(f"  - Labels: {label_str}")
                print()

            if closed_issues:
                print(f"### Closed ({len(closed_issues)})\n")
                for issue in closed_issues:
                    iid = issue.get('iid')
                    title = issue.get('title', 'Untitled')
                    url = issue.get('web_url', '')
                    print(f"- [#{iid} {title}]({url})")
                print()

        print("## Description\n")
        description = epic.get('description', 'No description')
        print(description if description else '*No description*')
        print()

    def print_milestone_info(self, data: Dict[str, Any]) -> None:
        """Print milestone information in markdown format.

        Args:
            data: Dictionary containing milestone, issues, and epic mapping.
        """
        milestone = data['milestone']
        issues = data.get('issues', [])
        epic_map = data.get('epic_map', {})
        self._print_milestone_markdown(milestone, issues, epic_map)

    def _print_milestone_markdown(
        self,
        milestone: Dict[str, Any],
        issues: List[Dict[str, Any]],
        epic_map: Dict[int, Dict[str, Any]]
    ) -> None:
        """Print milestone info in markdown format."""
        print(f"# Milestone %{milestone.get('iid')}: {milestone.get('title')}\n")

        print(f"**URL:** {milestone.get('web_url')}  ")
        print(f"**State:** {milestone.get('state')}  ")

        if milestone.get('start_date'):
            print(f"**Start Date:** {milestone['start_date']}  ")

        if milestone.get('due_date'):
            print(f"**Due Date:** {milestone['due_date']}  ")

        # Calculate progress
        total_issues = len(issues)
        closed_issues = len([i for i in issues if i.get('state') == 'closed'])
        print(f"**Progress:** {closed_issues}/{total_issues} issues closed  ")

        print(f"\n**Created:** {milestone.get('created_at')}  ")
        print(f"**Updated:** {milestone.get('updated_at')}  ")

        # Group issues by epic
        print(f"\n## Epic Breakdown\n")

        if not issues:
            print("*No issues in this milestone*\n")
        else:
            # Group issues by epic_iid
            issues_by_epic = {}
            issues_without_epic = []

            for issue in issues:
                epic_iid = issue.get('epic_iid')
                if epic_iid:
                    if epic_iid not in issues_by_epic:
                        issues_by_epic[epic_iid] = []
                    issues_by_epic[epic_iid].append(issue)
                else:
                    issues_without_epic.append(issue)

            # Print issues grouped by epic
            for epic_iid, epic_issues in sorted(issues_by_epic.items()):
                epic_data = epic_map.get(epic_iid)
                if epic_data:
                    epic_title = epic_data.get('title', 'Unknown')
                    print(f"### Epic &{epic_iid}: {epic_title}\n")
                else:
                    print(f"### Epic &{epic_iid}\n")

                for issue in epic_issues:
                    iid = issue.get('iid')
                    title = issue.get('title', 'Untitled')
                    state = issue.get('state', 'unknown')
                    print(f"- #{iid} {title} `[{state}]`")
                print()

            # Print issues without epic
            if issues_without_epic:
                print("### No Epic\n")
                for issue in issues_without_epic:
                    iid = issue.get('iid')
                    title = issue.get('title', 'Untitled')
                    state = issue.get('state', 'unknown')
                    print(f"- #{iid} {title} `[{state}]`")
                print()

        print("## Description\n")
        description = milestone.get('description', 'No description')
        print(description if description else '*No description*')
        print()

    def load_mr(self, mr_ref: str) -> Dict[str, Any]:
        """Load merge request information from GitLab.

        Args:
            mr_ref: MR reference (number, URL, or !number format).

        Returns:
            Dictionary containing MR data.

        Raises:
            GlabError: If loading fails.
        """
        # Remove ! prefix if present
        if mr_ref.startswith('!'):
            mr_ref = mr_ref[1:]

        # Parse URL if provided
        if '://' in mr_ref:
            # Extract MR number from URL
            # Format: https://gitlab.../group/project/-/merge_requests/123
            if '/-/merge_requests/' in mr_ref:
                mr_ref = mr_ref.split('/-/merge_requests/')[-1].split('/')[0].split('?')[0]
            else:
                raise ValueError(f"Invalid MR URL format: {mr_ref}")

        if not mr_ref.isdigit():
            raise ValueError(f"Invalid MR reference: {mr_ref}")

        logger.debug(f"Loading MR !{mr_ref}")

        # Use glab mr view command
        cmd = ['mr', 'view', mr_ref, '--output', 'json']
        output = self._run_glab_command(cmd)
        mr_data = json.loads(output)

        return {'mr': mr_data}

    def print_mr_info(self, data: Dict[str, Any]) -> None:
        """Print merge request information in markdown format.

        Args:
            data: Dictionary containing MR data.
        """
        mr = data['mr']
        print(f"# MR !{mr.get('iid')}: {mr.get('title')}\n")

        print(f"**URL:** {mr.get('web_url')}  ")
        print(f"**State:** {mr.get('state')}  ")
        print(f"**Author:** {mr.get('author', {}).get('name', 'Unknown')}  ")

        if mr.get('draft'):
            print(f"**Draft:** Yes  ")

        if mr.get('source_branch'):
            print(f"**Source Branch:** `{mr['source_branch']}`  ")

        if mr.get('target_branch'):
            print(f"**Target Branch:** `{mr['target_branch']}`  ")

        labels = mr.get('labels', [])
        if labels:
            print(f"**Labels:** {', '.join([f'`{l}`' for l in labels])}  ")

        assignees = mr.get('assignees', [])
        if assignees:
            names = [a.get('name', a.get('username')) for a in assignees]
            print(f"**Assignees:** {', '.join(names)}  ")

        reviewers = mr.get('reviewers', [])
        if reviewers:
            names = [r.get('name', r.get('username')) for r in reviewers]
            print(f"**Reviewers:** {', '.join(names)}  ")

        if mr.get('milestone'):
            print(f"**Milestone:** {mr['milestone'].get('title')}  ")

        print(f"\n**Created:** {mr.get('created_at')}  ")
        print(f"**Updated:** {mr.get('updated_at')}  ")

        if mr.get('merged_at'):
            print(f"**Merged:** {mr['merged_at']}  ")

        if mr.get('pipeline'):
            pipeline_status = mr['pipeline'].get('status', 'unknown')
            print(f"**Pipeline Status:** {pipeline_status}  ")

        print("\n## Description\n")
        description = mr.get('description', 'No description')
        print(description if description else '*No description*')
        print()


def cmd_create(args) -> int:
    """Handle the 'create' subcommand.

    Args:
        args: Parsed command-line arguments.

    Returns:
        Exit code (0 for success, 1 for error).
    """
    if not args.yaml_file.exists():
        logger.error(f"YAML file not found: {args.yaml_file}")
        return 1

    try:
        # Load configuration
        config_path = Path(args.config) if args.config else None
        config = Config(config_path)

        creator = EpicIssueCreator(
            config=config,
            dry_run=args.dry_run
        )
        creator.process_yaml_file(args.yaml_file)
        creator.print_summary()
        return 0
    except FileNotFoundError as e:
        logger.error(str(e))
        return 1
    except (GlabError, ValueError, yaml.YAMLError) as e:
        logger.error(f"Error: {e}")
        return 1


def cmd_load(args) -> int:
    """Handle the 'load' subcommand.

    Args:
        args: Parsed command-line arguments.

    Returns:
        Exit code (0 for success, 1 for error).
    """
    try:
        # Load configuration
        config_path = Path(args.config) if args.config else None
        config = Config(config_path)

        loader = TicketLoader(config=config)

        # Determine resource type
        reference = args.reference
        resource_type = 'issue'  # default

        # Check if --type is specified
        if hasattr(args, 'type') and args.type:
            resource_type = args.type
        else:
            # Auto-detect based on reference format
            if reference.startswith('!'):
                resource_type = 'mr'
            elif reference.startswith('&'):
                resource_type = 'epic'
            elif reference.startswith('%'):
                resource_type = 'milestone'
            elif '/-/merge_requests/' in reference:
                resource_type = 'mr'
            elif '/-/epics/' in reference:
                resource_type = 'epic'
            elif '/-/milestones/' in reference:
                resource_type = 'milestone'
            # Otherwise assume issue (default behavior)

        if resource_type == 'mr':
            # Load merge request
            data = loader.load_mr(reference)
            loader.print_mr_info(data)
        elif resource_type == 'epic':
            # Load epic with issues
            data = loader.load_epic_with_issues(reference)
            loader.print_epic_info(data)
        elif resource_type == 'milestone':
            # Load milestone with issues and epics
            data = loader.load_milestone_with_issues(reference)
            loader.print_milestone_info(data)
        else:
            # Load issue with epic
            data = loader.load_ticket_with_epic(reference)
            loader.print_ticket_info(data)

        return 0
    except FileNotFoundError as e:
        logger.error(str(e))
        return 1
    except (GlabError, ValueError, json.JSONDecodeError) as e:
        logger.error(f"Error: {e}")
        return 1


class SearchHandler:
    """Handles search operations for GitLab issues and epics."""

    def __init__(self, config: Config) -> None:
        """Initialize the search handler.

        Args:
            config: Configuration object with defaults.
        """
        self.config = config

    def _run_glab_command(self, cmd: List[str]) -> str:
        """Run a glab command and return its output.

        Args:
            cmd: List of command arguments to pass to glab.

        Returns:
            Command output as a string.

        Raises:
            GlabError: If the command fails.
        """
        full_cmd = ['glab'] + cmd

        try:
            logger.debug(f"Executing: {' '.join(full_cmd)}")
            result = subprocess.run(
                full_cmd,
                capture_output=True,
                text=True,
                check=True
            )
            return result.stdout.strip()
        except subprocess.CalledProcessError as e:
            error_msg = f"Command failed: {' '.join(full_cmd)}\n{e.stderr}"
            logger.error(error_msg)
            raise GlabError(error_msg) from e
        except FileNotFoundError:
            error_msg = "glab command not found. Please install glab CLI."
            logger.error(error_msg)
            raise GlabError(error_msg)

    def search_issues(
        self,
        query: str,
        state: str = 'all',
        limit: int = 20
    ) -> List[Dict[str, Any]]:
        """Search for issues matching a query.

        Args:
            query: Search text for title and description.
            state: Filter by state ('opened', 'closed', 'all').
            limit: Maximum number of results to return.

        Returns:
            List of issue dictionaries.

        Raises:
            GlabError: If search fails.
        """
        # Build API endpoint for current project
        api_endpoint = f"projects/:fullpath/issues?search={urllib.parse.quote(query)}"

        if state != 'all':
            api_endpoint += f"&state={state}"

        api_endpoint += f"&per_page={limit}"

        output = self._run_glab_command(['api', api_endpoint])

        if not output:
            return []

        return json.loads(output)

    def search_epics(
        self,
        query: str,
        state: str = 'all',
        limit: int = 20
    ) -> List[Dict[str, Any]]:
        """Search for epics matching a query.

        Args:
            query: Search text for title and description.
            state: Filter by state ('opened', 'closed', 'all').
            limit: Maximum number of results to return.

        Returns:
            List of epic dictionaries.

        Raises:
            GlabError: If search fails.
            ValueError: If group is not specified.
        """
        group_path = self.config.get_default_group()
        if not group_path:
            raise ValueError(
                "Group path is required for epic search.\n"
                "Please set 'default_group' in your glab_config.yaml file."
            )

        encoded_group = urllib.parse.quote(group_path, safe='')
        api_endpoint = f"groups/{encoded_group}/epics?search={urllib.parse.quote(query)}"

        if state != 'all':
            api_endpoint += f"&state={state}"

        api_endpoint += f"&per_page={limit}"

        output = self._run_glab_command(['api', api_endpoint])

        if not output:
            return []

        return json.loads(output)

    def search_milestones(
        self,
        query: str,
        state: str = 'all',
        limit: int = 20
    ) -> List[Dict[str, Any]]:
        """Search for milestones matching a query.

        Args:
            query: Search text for title.
            state: Filter by state ('active', 'closed', 'all').
            limit: Maximum number of results to return.

        Returns:
            List of milestone dictionaries.

        Raises:
            GlabError: If search fails.
        """
        # Use group API if default_group is configured, otherwise use project API
        group_path = self.config.get_default_group()

        if group_path:
            # Use group milestones API
            encoded_group = urllib.parse.quote(group_path, safe='')
            api_endpoint = f"groups/{encoded_group}/milestones?search={urllib.parse.quote(query)}"
        else:
            # Use project milestones API
            api_endpoint = f"projects/:fullpath/milestones?search={urllib.parse.quote(query)}"

        if state != 'all':
            api_endpoint += f"&state={state}"

        api_endpoint += f"&per_page={limit}"

        output = self._run_glab_command(['api', api_endpoint])

        if not output:
            return []

        return json.loads(output)

    def print_issues(
        self,
        issues: List[Dict[str, Any]],
        query: str
    ) -> None:
        """Print search results for issues in text format.

        Args:
            issues: List of issue dictionaries.
            query: The search query used.
        """
        print(f"\n=== ISSUES matching \"{query}\" ===\n")

        if not issues:
            print("No issues found")
            return

        for issue in issues:
            iid = issue.get('iid')
            title = issue.get('title', 'Untitled')
            state = issue.get('state', 'unknown')
            labels = issue.get('labels', [])
            url = issue.get('web_url', '')

            print(f"#{iid} {title}")
            label_str = ', '.join(labels) if labels else 'none'
            print(f"    State: {state} | Labels: {label_str}")
            print(f"    URL: {url}\n")

        print(f"Found {len(issues)} issue{'s' if len(issues) != 1 else ''}")

    def print_epics(
        self,
        epics: List[Dict[str, Any]],
        query: str
    ) -> None:
        """Print search results for epics in text format.

        Args:
            epics: List of epic dictionaries.
            query: The search query used.
        """
        print(f"\n=== EPICS matching \"{query}\" ===\n")

        if not epics:
            print("No epics found")
            return

        for epic in epics:
            iid = epic.get('iid')
            title = epic.get('title', 'Untitled')
            state = epic.get('state', 'unknown')
            labels = epic.get('labels', [])
            url = epic.get('web_url', '')

            print(f"&{iid} {title}")
            label_str = ', '.join(labels) if labels else 'none'
            print(f"    State: {state} | Labels: {label_str}")
            print(f"    URL: {url}\n")

        print(f"Found {len(epics)} epic{'s' if len(epics) != 1 else ''}")

    def print_milestones(
        self,
        milestones: List[Dict[str, Any]],
        query: str
    ) -> None:
        """Print search results for milestones in text format.

        Args:
            milestones: List of milestone dictionaries.
            query: The search query used.
        """
        print(f"\n=== MILESTONES matching \"{query}\" ===\n")

        if not milestones:
            print("No milestones found")
            return

        for milestone in milestones:
            iid = milestone.get('iid')
            title = milestone.get('title', 'Untitled')
            state = milestone.get('state', 'unknown')
            url = milestone.get('web_url', '')
            due_date = milestone.get('due_date', 'N/A')

            print(f"%{iid} {title}")
            print(f"    State: {state} | Due: {due_date}")
            print(f"    URL: {url}\n")

        print(f"Found {len(milestones)} milestone{'s' if len(milestones) != 1 else ''}")


def cmd_search(args) -> int:
    """Handle the 'search' subcommand.

    Args:
        args: Parsed command-line arguments.

    Returns:
        Exit code (0 for success, 1 for error).
    """
    try:
        # Load configuration
        config_path = Path(args.config) if args.config else None
        config = Config(config_path)

        searcher = SearchHandler(config=config)

        if args.type == 'issues':
            results = searcher.search_issues(
                query=args.query,
                state=args.state,
                limit=args.limit
            )
            searcher.print_issues(results, args.query)
        elif args.type == 'epics':
            results = searcher.search_epics(
                query=args.query,
                state=args.state,
                limit=args.limit
            )
            searcher.print_epics(results, args.query)
        elif args.type == 'milestones':
            results = searcher.search_milestones(
                query=args.query,
                state=args.state,
                limit=args.limit
            )
            searcher.print_milestones(results, args.query)
        else:
            logger.error(f"Unknown search type: {args.type}")
            return 1

        return 0
    except FileNotFoundError as e:
        logger.error(str(e))
        return 1
    except (GlabError, ValueError, json.JSONDecodeError) as e:
        logger.error(f"Error: {e}")
        return 1


def cmd_comment(args) -> int:
    """Handle the 'comment' subcommand - post review from YAML file to MR.

    Posts individual comments on specific lines in the MR diff for each finding.

    Args:
        args: Parsed command-line arguments.

    Returns:
        Exit code (0 for success, 1 for error).
    """
    try:
        # Check if review file exists
        review_file = Path(args.review_file)
        if not review_file.exists():
            logger.error(f"Review file not found: {review_file}")
            return 1

        # Load review YAML
        with open(review_file, 'r') as f:
            review_data = yaml.safe_load(f)

        # Validate required fields
        if 'findings' not in review_data:
            logger.error("Review YAML must contain 'findings' field")
            return 1

        # Get MR number from args or from YAML
        mr_number = args.mr_number
        if mr_number is None:
            mr_number = review_data.get('mr_number')
        if mr_number is None:
            logger.error("MR number must be specified via --mr or in review YAML")
            return 1

        # Get MR details to obtain commit SHAs
        logger.debug(f"Fetching MR !{mr_number} details")
        mr_info_cmd = ['glab', 'mr', 'view', str(mr_number), '--output', 'json']
        result = subprocess.run(mr_info_cmd, capture_output=True, text=True, check=True)
        mr_info = json.loads(result.stdout)

        # Extract commit SHAs for posting diff comments
        head_sha = mr_info.get('sha') or mr_info.get('diff_refs', {}).get('head_sha')
        base_sha = mr_info.get('diff_refs', {}).get('base_sha')

        if not head_sha or not base_sha:
            logger.error("Could not get commit SHAs from MR. Falling back to general comment.")
            # Fallback to single comment
            return post_general_comment(mr_number, review_data, args.dry_run)

        # All findings with locations become inline comments
        # If no line number specified, use line 1
        # Group locations by file to avoid duplicate comments
        findings = review_data.get('findings', [])
        inline_findings = []

        for finding in findings:
            # Get locations (could be single 'location' or multiple 'locations')
            locations = finding.get('locations', [])
            if 'location' in finding:
                locations = [finding['location']]

            if not locations:
                logger.warning(f"Finding '{finding.get('title')}' has no location, skipping")
                continue

            # Add line numbers if missing (default to line 1)
            normalized_locations = []
            for loc in locations:
                if ':' not in loc:
                    # No line number, add :1
                    normalized_locations.append(f"{loc}:1")
                else:
                    normalized_locations.append(loc)

            # Group locations by file to avoid duplicates
            # For each file, only post one comment on the first location
            files_seen = {}
            for loc in normalized_locations:
                file_path = loc.rsplit(':', 1)[0]
                if file_path not in files_seen:
                    files_seen[file_path] = loc
                    # Create a modified finding with all locations in this file
                    file_locations = [l for l in normalized_locations if l.startswith(file_path + ':')]
                    modified_finding = finding.copy()
                    if len(file_locations) > 1:
                        # Add note about other lines in the same file
                        modified_finding['_extra_locations'] = file_locations[1:]
                    inline_findings.append((modified_finding, [files_seen[file_path]]))

        # Post all findings as inline comments
        posted_count = 0
        failed_count = 0

        for finding, locations in inline_findings:
            for location in locations:
                success = post_inline_comment(
                    mr_number=mr_number,
                    finding=finding,
                    location=location,
                    base_sha=base_sha,
                    head_sha=head_sha,
                    dry_run=args.dry_run
                )

                if success:
                    posted_count += 1
                else:
                    failed_count += 1

        if args.dry_run:
            print(f"\n[DRY RUN] Would post {posted_count} inline comments to MR !{mr_number}")
            if failed_count > 0:
                print(f"[DRY RUN] {failed_count} comments would fail to post")
            return 0

        logger.info(f"✓ Posted {posted_count} inline comments to MR !{mr_number}")
        if failed_count > 0:
            logger.warning(f"⚠ {failed_count} inline comments failed to post")

        return 0

    except FileNotFoundError as e:
        logger.error(f"File error: {e}")
        return 1
    except subprocess.CalledProcessError as e:
        logger.error(f"Command failed: {e.stderr}")
        return 1
    except (ValueError, yaml.YAMLError, json.JSONDecodeError) as e:
        logger.error(f"Error: {e}")
        return 1


def post_inline_comment(
    mr_number: int,
    finding: Dict[str, Any],
    location: str,
    base_sha: str,
    head_sha: str,
    dry_run: bool = False
) -> bool:
    """Post an inline comment on a specific line in the MR diff.

    Args:
        mr_number: MR number
        finding: Finding dictionary from review YAML
        location: File location string (e.g., "path/to/file.cc:123")
        base_sha: Base commit SHA
        head_sha: Head commit SHA
        dry_run: If True, only print what would be done

    Returns:
        True if comment posted successfully, False otherwise
    """
    try:
        # Parse location (format: "path/to/file.cc:123" or "path/to/file.cc:123-145")
        if ':' not in location:
            logger.warning(f"Invalid location format: {location} (expected 'file:line')")
            return False

        file_path, line_part = location.rsplit(':', 1)

        # Handle line ranges (use start line)
        if '-' in line_part:
            line_num = int(line_part.split('-')[0])
        else:
            line_num = int(line_part)

        # Format comment body
        severity = finding.get('severity', 'Unknown')
        title = finding.get('title', 'Untitled')
        description = finding.get('description', '').strip()
        fix = finding.get('fix', '').strip()
        extra_locations = finding.get('_extra_locations', [])

        comment_body = f"**{severity}: {title}**\n\n{description}"

        # Add other affected lines in the same file
        if extra_locations:
            lines = [loc.split(':')[-1] for loc in extra_locations]
            comment_body += f"\n\n**Also affects lines:** {', '.join(lines)}"

        if fix:
            comment_body += f"\n\n**Fix:**\n```\n{fix}\n```"

        if dry_run:
            print(f"\n[DRY RUN] Would post comment on {file_path}:{line_num}")
            print(f"  Severity: {severity}")
            print(f"  Title: {title}")
            return True

        # Prepare JSON payload with position data including old_line: null
        import json as json_module
        payload = {
            "body": comment_body,
            "position": {
                "position_type": "text",
                "old_path": file_path,
                "new_path": file_path,
                "old_line": None,  # null for new files
                "new_line": line_num,
                "base_sha": base_sha,
                "start_sha": base_sha,
                "head_sha": head_sha
            }
        }

        # Post using GitLab API via glab with JSON input and Content-Type header
        cmd = [
            'glab', 'api',
            f'projects/:id/merge_requests/{mr_number}/discussions',
            '--method', 'POST',
            '--header', 'Content-Type: application/json',
            '--input', '-'
        ]

        logger.debug(f"Posting comment to {file_path}:{line_num}")
        result = subprocess.run(
            cmd,
            input=json_module.dumps(payload),
            capture_output=True,
            text=True,
            check=True
        )

        logger.info(f"✓ Posted comment on {file_path}:{line_num}")
        return True

    except ValueError as e:
        logger.error(f"Invalid line number in location: {location}: {e}")
        return False
    except subprocess.CalledProcessError as e:
        logger.error(f"Failed to post comment on {location}: {e.stderr}")
        return False
    except Exception as e:
        logger.error(f"Error posting comment on {location}: {e}")
        return False


def post_general_comment(mr_number: int, review_data: Dict[str, Any], dry_run: bool = False) -> int:
    """Post a general comment with all findings (fallback when inline comments fail).

    Args:
        mr_number: MR number
        review_data: Review data from YAML
        dry_run: If True, only print what would be done

    Returns:
        Exit code (0 for success, 1 for error)
    """
    try:
        comment = format_review_comment(review_data)

        if dry_run:
            print(f"[DRY RUN] Would post general comment to MR !{mr_number}:")
            print("=" * 80)
            print(comment)
            print("=" * 80)
            return 0

        cmd = ['glab', 'mr', 'comment', str(mr_number), '--message', comment]
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)

        logger.info(f"✓ Posted general comment to MR !{mr_number}")
        print(f"Comment posted: {result.stdout.strip()}")
        return 0

    except subprocess.CalledProcessError as e:
        logger.error(f"Failed to post general comment: {e.stderr}")
        return 1


def format_review_comment(review_data: Dict[str, Any]) -> str:
    """Format review YAML data into a markdown comment.

    Args:
        review_data: Review data from YAML file.

    Returns:
        Formatted markdown comment.
    """
    lines = []

    # Header
    title = review_data.get('title', 'Code Review')
    review_date = review_data.get('review_date', '')
    lines.append(f"# Code Review: {title}")
    if review_date:
        lines.append(f"**Review Date:** {review_date}")
    lines.append("")

    # Group findings by severity
    findings = review_data.get('findings', [])
    severity_groups = {}
    for finding in findings:
        severity = finding.get('severity', 'Unknown')
        if severity not in severity_groups:
            severity_groups[severity] = []
        severity_groups[severity].append(finding)

    # Output findings by severity (Critical, High, Medium, Low)
    severity_order = ['Critical', 'High', 'Medium', 'Low']
    finding_num = 1

    for severity in severity_order:
        if severity not in severity_groups:
            continue

        lines.append(f"## {severity} Priority Issues")
        lines.append("")

        for finding in severity_groups[severity]:
            title = finding.get('title', 'Untitled')
            description = finding.get('description', '').strip()
            location = finding.get('location')
            locations = finding.get('locations', [])
            fix = finding.get('fix', '').strip()

            lines.append(f"### {finding_num}. {title}")
            finding_num += 1

            if description:
                lines.append(f"{description}")
                lines.append("")

            if location:
                lines.append(f"**Location:** `{location}`")
            elif locations:
                lines.append(f"**Locations:**")
                for loc in locations:
                    lines.append(f"- `{loc}`")

            if fix:
                lines.append(f"\n**Fix:**")
                lines.append(f"```")
                lines.append(fix)
                lines.append(f"```")

            lines.append("")

    return "\n".join(lines)


def cmd_create_mr(args) -> int:
    """Handle the 'create-mr' subcommand - create merge request from current branch.

    Args:
        args: Parsed command-line arguments.

    Returns:
        Exit code (0 for success, 1 for error).
    """
    try:
        # Build glab mr create command
        cmd = ['glab', 'mr', 'create']

        if args.title:
            cmd.extend(['--title', args.title])

        if args.description:
            cmd.extend(['--description', args.description])

        if args.draft:
            cmd.append('--draft')

        if args.assignee:
            for assignee in args.assignee:
                cmd.extend(['--assignee', assignee])

        if args.reviewer:
            for reviewer in args.reviewer:
                cmd.extend(['--reviewer', reviewer])

        if args.label:
            for label in args.label:
                cmd.extend(['--label', label])

        if args.milestone:
            cmd.extend(['--milestone', args.milestone])

        if args.target_branch:
            cmd.extend(['--target-branch', args.target_branch])

        if args.fill:
            cmd.append('--fill')

        if args.web:
            cmd.append('--web')

        if args.dry_run:
            print(f"[DRY RUN] Would execute: {' '.join(cmd)}")
            return 0

        # Execute command
        logger.debug(f"Executing: {' '.join(cmd)}")
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            check=True
        )

        logger.info("✓ Merge request created")
        print(result.stdout.strip())
        return 0

    except subprocess.CalledProcessError as e:
        logger.error(f"Command failed: {e.stderr}")
        return 1
    except Exception as e:
        logger.error(f"Error: {e}")
        return 1


def main() -> int:
    """Main entry point for the script.

    Returns:
        Exit code (0 for success, 1 for error).
    """
    parser = argparse.ArgumentParser(
        description='GitLab Epic and Issue management tool',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Create issues from YAML
  %(prog)s create epic_definition.yaml
  %(prog)s create --dry-run epic_definition.yaml

  # Load issue information (with dependencies, markdown output)
  %(prog)s load 113
  %(prog)s load https://gitlab.example.com/group/project/-/issues/113

  # Load epic information (with all issues in the epic, markdown output)
  %(prog)s load &21
  %(prog)s load https://gitlab.example.com/groups/mygroup/-/epics/21
  %(prog)s load 21 --type epic

  # Load milestone information (with all issues and epics, markdown output)
  %(prog)s load %%123
  %(prog)s load https://gitlab.example.com/group/project/-/milestones/123
  %(prog)s load 123 --type milestone

  # Load merge request information (markdown output)
  %(prog)s load !134
  %(prog)s load 134 --type mr
  %(prog)s load https://gitlab.example.com/group/project/-/merge_requests/134

  # Search issues, epics, and milestones (text output)
  %(prog)s search issues "streaming"
  %(prog)s search issues "SRT" --state opened
  %(prog)s search epics "video"
  %(prog)s search milestones "v1.0" --state active

  # Post review comment from YAML to merge request
  %(prog)s comment planning/reviews/MR134-review.yaml
  %(prog)s comment planning/reviews/MR134-review.yaml --mr 134 --dry-run

  # Create merge request from current branch
  %(prog)s create-mr --title "Add feature X" --draft
  %(prog)s create-mr --fill --reviewer alice --label "type::feature"
        """
    )

    parser.add_argument(
        '--verbose',
        action='store_true',
        help='Enable verbose logging'
    )

    parser.add_argument(
        '--config',
        type=str,
        help='Path to config file (default: ./glab_config.yaml in current directory)'
    )

    subparsers = parser.add_subparsers(dest='command', help='Available commands')

    # Create subcommand
    create_parser = subparsers.add_parser(
        'create',
        help='Create issues from YAML and link to epic',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
YAML format:
  epic:
    title: "My Epic Title"
    description: "Epic description"
    # OR use existing epic:
    # id: 123

  issues:
    - title: "Issue 1"
      description: "Description"
      labels:
        - "bug"
        - "priority::high"
      assignee: "username"
      milestone: "v1.0"
      due_date: "2025-01-15"
        """
    )
    create_parser.add_argument(
        'yaml_file',
        type=Path,
        help='Path to YAML file containing epic and issue definitions'
    )
    create_parser.add_argument(
        '--dry-run',
        action='store_true',
        help='Preview commands without executing them'
    )

    # Load subcommand
    load_parser = subparsers.add_parser(
        'load',
        help='Load ticket (issue), epic, or milestone information from GitLab',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Load issue (auto-detected, markdown output)
  glab_tasks_management.py load 113
  glab_tasks_management.py load https://gitlab.example.com/group/project/-/issues/113

  # Load epic (auto-detected from & prefix or URL, markdown output)
  glab_tasks_management.py load &21
  glab_tasks_management.py load https://gitlab.example.com/groups/mygroup/-/epics/21

  # Load milestone (auto-detected from %% prefix or URL, markdown output)
  glab_tasks_management.py load %%123
  glab_tasks_management.py load https://gitlab.example.com/group/project/-/milestones/123

  # Load with explicit type specification (markdown output)
  glab_tasks_management.py load 21 --type epic
  glab_tasks_management.py load 123 --type milestone
        """
    )
    load_parser.add_argument(
        'reference',
        type=str,
        help='Resource reference: number, URL, #number (issue), &number (epic), or %%number (milestone)'
    )
    load_parser.add_argument(
        '--type',
        choices=['issue', 'epic', 'milestone', 'mr'],
        help='Resource type (auto-detected if not specified)'
    )


    # Search subcommand
    search_parser = subparsers.add_parser(
        'search',
        help='Search for issues, epics, or milestones by text',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Search issues (all states by default, text output)
  glab_tasks_management.py search issues "streaming"
  glab_tasks_management.py search issues "SRT" --state opened
  glab_tasks_management.py search issues "SRT" --state closed

  # Search epics (text output)
  glab_tasks_management.py search epics "video"
  glab_tasks_management.py search epics "streaming" --state opened

  # Search milestones (text output)
  glab_tasks_management.py search milestones "v1.0"
  glab_tasks_management.py search milestones "release" --state active

  # Limit results
  glab_tasks_management.py search issues "camera" --limit 10
        """
    )
    search_parser.add_argument(
        'type',
        choices=['issues', 'epics', 'milestones'],
        help='Type of resource to search'
    )
    search_parser.add_argument(
        'query',
        type=str,
        help='Search query text (searches title and description)'
    )
    search_parser.add_argument(
        '--state',
        choices=['opened', 'closed', 'active', 'all'],
        default='all',
        help='Filter by state (default: all). Use "active" for milestones.'
    )
    search_parser.add_argument(
        '--limit',
        type=int,
        default=20,
        help='Maximum number of results (default: 20)'
    )

    # Comment subcommand
    comment_parser = subparsers.add_parser(
        'comment',
        help='Post review comment from YAML file to merge request',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Post review to MR (MR number from YAML)
  glab_tasks_management.py comment planning/reviews/MR134-review.yaml

  # Post review to specific MR (override YAML)
  glab_tasks_management.py comment planning/reviews/MR134-review.yaml --mr 134

  # Preview comment without posting
  glab_tasks_management.py comment planning/reviews/MR134-review.yaml --dry-run
        """
    )
    comment_parser.add_argument(
        'review_file',
        type=str,
        help='Path to review YAML file (e.g., planning/reviews/MR134-review.yaml)'
    )
    comment_parser.add_argument(
        '--mr',
        dest='mr_number',
        type=int,
        help='MR number (overrides value from YAML)'
    )
    comment_parser.add_argument(
        '--dry-run',
        action='store_true',
        help='Preview comment without posting'
    )

    # Create-MR subcommand
    create_mr_parser = subparsers.add_parser(
        'create-mr',
        help='Create merge request from current branch',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Create MR with interactive prompts
  glab_tasks_management.py create-mr

  # Create MR with title and description
  glab_tasks_management.py create-mr --title "Add feature X" --description "Implements feature X"

  # Create draft MR
  glab_tasks_management.py create-mr --draft --fill

  # Create MR with reviewers and labels
  glab_tasks_management.py create-mr --reviewer alice --reviewer bob --label "type::feature"

  # Preview without creating
  glab_tasks_management.py create-mr --title "Test" --dry-run
        """
    )
    create_mr_parser.add_argument(
        '--title',
        type=str,
        help='MR title'
    )
    create_mr_parser.add_argument(
        '--description',
        type=str,
        help='MR description'
    )
    create_mr_parser.add_argument(
        '--draft',
        action='store_true',
        help='Mark MR as draft'
    )
    create_mr_parser.add_argument(
        '--assignee',
        action='append',
        help='Assignee username (can be repeated)'
    )
    create_mr_parser.add_argument(
        '--reviewer',
        action='append',
        help='Reviewer username (can be repeated)'
    )
    create_mr_parser.add_argument(
        '--label',
        action='append',
        help='Label to add (can be repeated)'
    )
    create_mr_parser.add_argument(
        '--milestone',
        type=str,
        help='Milestone title'
    )
    create_mr_parser.add_argument(
        '--target-branch',
        type=str,
        help='Target branch (default: default branch)'
    )
    create_mr_parser.add_argument(
        '--fill',
        action='store_true',
        help='Fill in title and description from commits'
    )
    create_mr_parser.add_argument(
        '--web',
        action='store_true',
        help='Open MR in web browser after creation'
    )
    create_mr_parser.add_argument(
        '--dry-run',
        action='store_true',
        help='Preview command without creating MR'
    )

    args = parser.parse_args()

    if args.verbose:
        logger.setLevel(logging.DEBUG)

    if not args.command:
        parser.print_help()
        return 1

    try:
        if args.command == 'create':
            return cmd_create(args)
        elif args.command == 'load':
            return cmd_load(args)
        elif args.command == 'search':
            return cmd_search(args)
        elif args.command == 'comment':
            return cmd_comment(args)
        elif args.command == 'create-mr':
            return cmd_create_mr(args)
        else:
            parser.print_help()
            return 1
    except KeyboardInterrupt:
        logger.info("\nOperation cancelled by user")
        return 130


if __name__ == '__main__':
    sys.exit(main())
