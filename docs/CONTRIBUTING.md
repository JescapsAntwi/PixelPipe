# 🤝 Contributing to PixelPipe

Thank you for your interest in contributing to PixelPipe! We welcome all kinds of contributions, including bug reports, feature requests, documentation improvements, and code enhancements.

## How to Contribute

1. **Fork the repository**
   - Click the "Fork" button at the top right of this repo.

2. **Clone your fork**
   ```bash
   git clone https://github.com/<your-username>/PixelPipe.git
   cd PixelPipe
   ```

3. **Create a new branch**
   ```bash
   git checkout -b my-feature-branch
   ```

4. **Make your changes**
   - Follow the existing code style and structure.
   - Add or update tests as needed.
   - Update documentation if your changes affect usage or behavior.

5. **Test your changes**
   - Run all tests to ensure nothing is broken.
   - Test infrastructure changes with `terraform plan`.
   - Test services and functions locally with Docker or the emulator.

6. **Commit and push**
   ```bash
   git add .
   git commit -m "Describe your change"
   git push origin my-feature-branch
   ```

7. **Open a Pull Request**
   - Go to your fork on GitHub and click "Compare & pull request".
   - Fill in the PR template and describe your changes clearly.

8. **Participate in the review**
   - Respond to feedback and make any requested changes.

## Code of Conduct

Please be respectful and considerate in all interactions. See [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) for details.

## Style Guide
- Use clear, descriptive commit messages.
- Follow PEP8 for Python code.
- Use Terraform best practices for infrastructure code.
- Write docstrings and comments where helpful.

## Reporting Issues
- Use [GitHub Issues](../../issues) to report bugs or request features.
- Provide as much detail as possible, including logs, error messages, and steps to reproduce.

## Questions?
If you have any questions, open an issue or start a discussion.

Thank you for helping make PixelPipe better!
