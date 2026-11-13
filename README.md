# g2ray

A self-hosted proxy setup that runs inside GitHub Codespaces.

## Quick Start

1. Fork this repository to your own account
2. Navigate to your fork and open the **Codespaces** tab under the Code button
3. Create a new codespace on the main branch
4. Wait a few minutes for the environment to build and initialize
5. Xray starts with the container. If VS Code asks to allow automatic tasks, allow them. The **Start g2ray** task publishes port 443 and prints the VLESS connection string in the integrated terminal.

## Connecting

Grab the link printed in the terminal and paste it into any compatible client (v2rayNG, Nekobox, etc.).
The link is printed only after Codespaces confirms that the forwarded port is public. If a client reports `-1` or the endpoint redirects to GitHub sign-in, rerun the **Start g2ray** task and use the newly printed link.

## Recovering a connection

If the endpoint stops responding, run the **Recover g2ray** task from the VS Code task list, or run:

```bash
bash .devcontainer/recover.sh
```

This generates a new UUID, updates both the workspace and running Xray configurations, restarts Xray, republishes port 443, and prints a new link only after the endpoint responds. Import that link into the client; the previous UUID will no longer work. The Codespaces hostname itself cannot be changed by this script. If the hostname is unavailable, create a new Codespace.

## Usage Limits

GitHub Codespaces provides **120 core-hours/month** on the free tier. Since this config uses 2 cores, that translates to roughly 60 hours per month. Make sure to stop your codespace when not actively using it to avoid burning through your quota.

## Compatibility

Works on most networks that aren't aggressively blocking GitHub infrastructure. If the default region doesn't work for you, try creating the codespace in a different datacenter.

## Disclaimer

This project is strictly experimental and intended for **educational and research purposes only**. It does not violate GitHub's Terms of Service. It uses GitHub Codespaces — a feature officially provided by GitHub — in its intended manner. No abuse, exploit, or unauthorized access is involved.

Users are solely responsible for how they use this software and must comply with all applicable local laws and regulations. The authors assume no liability for any misuse.

## License

MIT License — see [LICENSE](LICENSE) for details.
