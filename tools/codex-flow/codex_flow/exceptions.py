"""codex-flow error types."""


class CodexFlowError(Exception):
    """Base error for codex-flow."""


class ValidationError(CodexFlowError):
    """Raised when a request document fails validation."""


class WorkflowViolationError(CodexFlowError):
    """Raised when runtime safety rules are violated."""
