#!/bin/bash
# BasicForth — ARM64 Deploy Script Template
# Copyright (C) 2026 Brandon Blodget
# SPDX-License-Identifier: GPL-2.0-only
#
# Copy this file to deploy.sh and customize for your board:
#
#   cp deploy_template.sh deploy.sh
#   chmod +x deploy.sh
#   # Edit BOARD and BOARD_DIR below
#
# deploy.sh is in .gitignore and won't be committed.

BOARD="myboard"              # SSH hostname or user@host
BOARD_DIR="~/BasicForth"     # Remote directory

scp basicforth test_basicforth "$BOARD:$BOARD_DIR/"
echo "Deployed to $BOARD:$BOARD_DIR/"
