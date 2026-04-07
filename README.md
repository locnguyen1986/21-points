# 21-points

Automated PR review script that uses the GitHub CLI (`gh`) and `jq` to fetch open pull requests, analyze their diffs, and post review comments.

## Prerequisites

- [Bash](https://www.gnu.org/software/bash/) >= 4.0
- [GitHub CLI (`gh`)](https://cli.github.com/) — authenticated with `gh auth login`
- [jq](https://jqlang.github.io/jq/) — command-line JSON processor

## Usage

Run the script from the repository root. It auto-detects the current repo:

```bash
./review_prs.sh
```

Or pass a specific repository:

```bash
./review_prs.sh owner/repo
```

The script will:

1. Fetch all open PRs for the target repository.
2. Skip PRs that already have a Claude review comment.
3. Analyze each PR's diff for common issues (placeholder text, missing LICENSE, generic descriptions).
4. Post a review comment summarizing findings and a merge suggestion.

## Contributing

### Fork and clone

1. Fork the repository on GitHub.
2. Clone your fork locally:

   ```bash
   git clone https://github.com/<your-fork>/21-points.git
   cd 21-points
   ```

3. Add the upstream remote:

   ```bash
   git remote add upstream https://github.com/<upstream-owner>/21-points.git
   ```

### Branching strategy

- Create feature branches from `main`:

  ```bash
  git checkout main
  git pull upstream main
  git checkout -b feature/your-feature-name
  ```

- Keep branches focused on a single change.

### Pull request process

1. Push your branch to your fork.
2. Open a pull request against `main`.
3. Describe what changed and why in the PR description.
4. Request a review from at least one maintainer.
5. Address review feedback, then merge once approved.

### Commit message format

This project uses [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <description>
```

Examples:

- `feat(auth): add JWT validation`
- `fix(api): handle null response body`
- `docs(readme): update setup instructions`

Common types: `feat`, `fix`, `docs`, `chore`, `test`, `refactor`, `ci`.

## License

No license has been chosen for this project yet.
