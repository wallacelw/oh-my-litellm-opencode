#!/bin/bash
# ClickHouse init script — creates OpenLit tables on first start
set -e

clickhouse-client --user="${CLICKHOUSE_USER}" --password="${CLICKHOUSE_PASSWORD}" \
  --query="CREATE DATABASE IF NOT EXISTS ${CLICKHOUSE_DATABASE}"
