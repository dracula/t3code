### [T3 Code](https://github.com/pingdotgg/t3code)

#### Install using Bash

On macOS or Linux, run:

```bash
curl -fsSL https://raw.githubusercontent.com/dracula/t3code/main/install.sh | bash
```

The script imports and selects Dracula for your local T3 Code desktop/server environment. Offline clients apply it when they reconnect. If a compatible T3 CLI is unavailable, the script uses `npx`, which requires Node.js and npm. The `npx` fallback supports Apple Silicon macOS and x64/ARM64 Linux.

For a custom T3 directory, pass `--base-dir` or set `T3CODE_HOME`:

```bash
curl -fsSL https://raw.githubusercontent.com/dracula/t3code/main/install.sh | bash -s -- --base-dir /path/to/t3
```

#### Install using Git

If you use Git, clone the repository to install the theme and keep it up to date:

```bash
git clone https://github.com/dracula/t3code.git
cd t3code
bash install.sh
```

#### Install manually

Download the [GitHub `.zip` archive](https://github.com/dracula/t3code/archive/main.zip) and unzip it, or save [`Dracula.json`](./Dracula.json) directly.

#### Activating the theme

1. Open T3 Code and go to **Settings → Appearance**.
2. Click **Add a theme**.
3. Drag and drop [`Dracula.json`](./Dracula.json) onto the dialog (or click **Choose files** and select it).
4. Select **Dracula** from your theme list.
