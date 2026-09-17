# Quick Guide: Push .env.example to GitHub

Use this when you add environment template files and want to publish safely.

## 1) Commit and push

Run from project root:

```bash
git status
git add file
git commit -m "Add file template for AppDynamics settings"
git push
```

If this is a new branch without upstream:

```bash
git branch --show-current
git push -u origin <branch-name>
```

## 2) Basic troubleshooting

If push fails, check branch and remote:

```bash
git branch --show-current
git remote -v
```

If no remote exists:

```bash
git remote add origin <repo-url>
git push -u origin <branch-name>
```

If Git says nothing to commit, verify file name/path:

```bash
ls -la file
git status
```
