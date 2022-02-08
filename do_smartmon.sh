#!/bin/bash

# run smartmon.sh and create a temporary *.prom file
# mv  temporary *.prom file to destination for textfile_collector
# reason: textfile_collector should be able to read the *.prom file at any time

# create metrics                   in this file                                   move this file to destination to be imported by textfile_collector, node_exporter, Prometheus
/opt/smart_exporter/smartmon.sh > /opt/smart_exporter/smart_metrics.prom 2>&1  && sudo mv -f /opt/smart_exporter/smart_metrics.prom /service/node_exporter/textfile_collector/smart_metrics.prom 2>&1
