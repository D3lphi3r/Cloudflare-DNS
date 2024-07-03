# Cloudflare-DNS
Dymanic update DNS records using Cloudflare API

1. **Update JSON Config File**: Modify the necessary data within the JSON configuration file.
2. **Run Script**: Execute `./cloudflaredns` to complete the DNS update process.

You can also use the following parameters as needed:
- `-s` or `--skip`: Skips checking if your public IP has changed since the last run.
- `-l` or `--log`: Outputs logs to a file named `logs.txt` in the same directory.
- `-S` or `--Silent`: Disables console outputs to prevent errors if stdout is not allocated.
- `-i` or `-ids`: Obtains the MD5 hashes for each DNS record under your domain, which is useful for the initial run.

  Can be used with crontab or create as systemd service.
