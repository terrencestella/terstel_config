## Core Principles

- Never use emojis in code files or commit messages.
- Emojis in status line are acceptable.

## Commit Authorship

When committing code changes:
- Never add Claude as a commit author.
- Always commit using the default git settings

## Documentation Style

When creating or updating markdown documentation files:
- **Never create .md files unless explicitly instructed.**
- **Be extremely concise** - engineers scan, they don't read novels
- **Only include essential information** - what they need to know, not what's possible to explain
- **Prefer examples over prose** - show the pattern, not the theory
- **Assume technical competence** - skip obvious explanations
- **Front-load critical info** - put warnings and key concepts first
- **Delete verbose explanations** - if it takes more than 3 sentences, it's probably too long

Default to 1-2 sentence explanations. Only expand when complexity absolutely requires it.

## Project Scaffolding

When creating new projects, always include:

### Required Files
- `.env` (never commit)
- `.env.example` (commit with placeholders)
- `.gitignore` (must include .env patterns)
- `README.md`
- `CLAUDE.md` (project-specific)

### Directory Structure
- `src/` - source code
- `tests/` - testing
- `docs/` - documentation
- `.claude/` - project-specific Claude config

### .gitignore Requirements
Must always include:
- Environment files: `.env`, `.env.*`, `*.local`
- Dependencies: `node_modules/`, `__pycache__/`, `.venv/`, `venv/`
- Build outputs: `dist/`, `build/`, `*.pyc`, `*.pyo`
- IDE: `.vscode/`, `.idea/`, `*.swp`, `*.swo`
- OS: `.DS_Store`, `Thumbs.db`
- Claude local: `CLAUDE.local.md`

### Security Rules
- Never commit credentials or secrets
- Verify staged changes before commits
- All .env files stay in .gitignore
