# S.M.A.R.T.-disk-monitoring-for-Prometheus text_collector
==========================================

Prometheus `node_exporter` `text_collector` for S.M.A.R.T disk values

## Purpose
This text_collector is a customized version of the S.M.A.R.T. `text_collector` example from `node_exporter` github repo:
https://github.com/prometheus/node_exporter/tree/master/text_collector_examples

## Requirements
- Prometheus
- node_exporter
  - text_collector enabled for node_exporter
- Grafana >= 6.2.5
- smartmontools >= 7.0

## Set up

## How to add S.M.A.R.T. attributes
If you are missing some attributes you can extend the text_collector.
Add the desired attributes to `smartmon_attrs` array in `smartmon.sh`.

You get a list of your disks privided attributes by executing:
`sudo 	smartctl -i -H /dev/<sdx>`
`sudo 	smartctl -A /dev/<sdx>`


