#!/usr/bin/env python3

import argparse
import qbittorrentapi
import os

arg_parser = argparse.ArgumentParser(
    description="Randomize qBittorrent listening port",
    formatter_class=argparse.ArgumentDefaultsHelpFormatter,
)
arg_parser.add_argument(
    "--port-min",
    type=int,
    default=26000,
    help="Minimum port number " "(default: 26000)",
)
arg_parser.add_argument(
    "--port-max",
    type=int,
    default=26999,
    help="Maximum port number " "(default: 26999)",
)
arg_parser.add_argument(
    "--username",
    type=str,
    default=os.environ.get("QBITTORRENT_USERNAME", None),
    help="qBittorrent username",
)
arg_parser.add_argument(
    "--password",
    type=str,
    default=os.environ.get("QBITTORRENT_PASSWORD", None),
    help="qBittorrent password",
)
arg_parser.add_argument(
    "--base-url",
    type=str,
    default=os.environ.get("QBITTORRENT_BASE_URL", None),
    help="qBittorrent URL base",
)
args = arg_parser.parse_args()

if args.username is None:
    raise ValueError(
        "Username must be provided via --username or QBITTORRENT_USERNAME "
        "environment variable"
    )
if args.password is None:
    raise ValueError(
        "Password must be provided via --password or QBITTORRENT_PASSWORD "
        "environment variable"
    )
if args.base_url is None:
    raise ValueError(
        "URL Base must be provided via --base-url or QBITTORRENT_BASE_URL "
        "environment variable"
    )

qbt_client = qbittorrentapi.Client(
    username=args.username, password=args.password, host=args.base_url
)

listen_port = qbt_client.application.preferences.listen_port
print(f"Current listen_port: {listen_port}")

listen_port += 1
if listen_port > args.port_max:
    listen_port = args.port_min

qbt_client.application.preferences = dict(listen_port=(listen_port))

print(f"Updated listen_port to: {qbt_client.application.preferences.listen_port}")
