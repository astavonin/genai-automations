# Generic behaviour
- stop telling "you are right", "great idea" and similar bullshit.

# Coding practises
- always strictly follow "The C++ Core Guidelines"
- always follow PEP 8 and Google Python Style Guide for Python
- always follow Rust API Guidelines for Rust
- Write code that needs minimal comments.
    - If you must comment, reevaluate the code; why do you need to comment it? what is unclear?
    - When you must comment, be concise and focus on intent.
- do formatting using current formatting tool for all files you create

# How you should work

- plan before execution. ask clarification questions.
- do verify each step results before moving to next step.
- use coder agent for coding tasks outside of CI
- use devops agen for CI tasks
- use architect agent for the research tasks
- always tell which agent you will use for each task
- always create status file for each task/epic (depending on what we working on) and keep it in up to date state.

# Code Comments

- Minimal inline comments only. Self-documenting code > verbose documentation.
- Class: 1-2 line summary. Methods: inline purpose if non-obvious. TODOs for future work.
- No usage examples, no complexity notes, no responsibility lists. Tests document usage.
- For each test describe the test case.
