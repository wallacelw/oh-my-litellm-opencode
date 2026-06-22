#!/bin/bash
# ClickHouse init script — creates the OpenLit database on first start
# (OpenLit creates its own tables on first connection)
set -e

clickhouse-client --user="${CLICKHOUSE_USER}" --password="${CLICKHOUSE_PASSWORD}" \
  --query="CREATE DATABASE IF NOT EXISTS ${CLICKHOUSE_DATABASE}"
