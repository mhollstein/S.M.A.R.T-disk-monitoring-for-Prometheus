#!/bin/bash

# file: smartmon.sh
# Added more metric information, cciss metrics and FORCED_DEVICE_LIST by Michael Hollstein, 2022/01
#
# Script informed by the collectd monitoring script for smartmontools (using smartctl)
# by Samuel B. <samuel_._behan_(at)_dob_._sk> (c) 2012
# source at: http://devel.dob.sk/collectd-scripts/

# TODO: This probably needs to be a little more complex.  The raw numbers can have more
#       data in them than you'd think.
#       http://arstechnica.com/civis/viewtopic.php?p=22062211

# Formatting done via shfmt -i 2
# https://github.com/mvdan/sh

# Run script every 5 minutes
# crontab -e
# # Chef Name: smart_monitoring
# */5 * * * * /opt/smart_exporter/smartmon.sh > /service/node_exporter/textfile_collector/smart_metrics.prom 2>&1



#CM="/usr/bin/which smartctl"
SMARTCTL=/usr/sbin/smartctl    #$(eval "$CM")  # /usr/sbin/smartctl  # $(which smartctl) ... for crontab


# set your own  devices
# see also: hpssacli ctrl all show config
FORCED_DEVICE_LIST=$(cat << EOF
/dev/sda|cciss,00
/dev/sda|cciss,01
/dev/sda|cciss,02
/dev/sda|cciss,03
/dev/sda|cciss,04
/dev/sda|cciss,05
/dev/sda|cciss,06
/dev/sda|cciss,07
/dev/sda|cciss,08
/dev/sda|cciss,09
/dev/sda|cciss,10
/dev/sda|cciss,11
/dev/sda|cciss,12
/dev/sda|cciss,13
/dev/sdb|cciss,14
/dev/sdb|cciss,15
/dev/sdb|cciss,16
/dev/sdb|cciss,17
/dev/sdb|cciss,18
/dev/sdb|cciss,19
/dev/sdb|cciss,20
/dev/sdb|cciss,21
/dev/sdb|cciss,22
/dev/sdb|cciss,23
/dev/sdb|cciss,24
/dev/sdb|cciss,25
EOF
)
# Example:
#FORCED_DEVICE_LIST=$(cat << EOF
#/dev/sg3|scsi
#/dev/sg4|sat
#/dev/sg5|sat
#/dev/sg6|sat
#/dev/sg7|scsi
#/dev/sg8|sat
#/dev/sg9|sat
#/dev/sdc|sat
#EOF
#)

parse_smartctl_attributes_awk="$(
  cat <<'SMARTCTLAWK'
$1 ~ /^ *[0-9]+$/ && $2 ~ /^[a-zA-Z0-9_-]+$/ {
  gsub(/-/, "_");
  printf "%s_value{%s,smart_id=\"%s\"} %d\n", tolower($2), labels, $1, $4
  printf "%s_worst{%s,smart_id=\"%s\"} %d\n", tolower($2), labels, $1, $5
  printf "%s_threshold{%s,smart_id=\"%s\"} %d\n", tolower($2), labels, $1, $6
  printf "%s_raw_value{%s,smart_id=\"%s\"} %e\n", tolower($2), labels, $1, $10
}
SMARTCTLAWK
)"

smartmon_attrs="$(
  cat <<'SMARTMONATTRS'
#accumulated_power_on_time
airflow_temperature_cel
command_timeout
current_pending_sector
end_to_end_error
erase_fail_count
g_sense_error_rate
hardware_ecc_recovered
host_reads_mib
host_reads_32mib
host_writes_mib
host_writes_32mib
load_cycle_count
media_wearout_indicator
multi_zone_error_rate
wear_leveling_count
nand_writes_1gib
offline_uncorrectable
percent_lifetime_remain
power_cycle_count
power_off_retract_count
power_on_hours
program_fail_count
raw_read_error_rate
reallocated_event_count
reallocated_sector_ct
reallocate_nand_blk_cnt
reported_uncorrect
sata_downshift_count
seek_error_rate
spin_retry_count
spin_up_time
start_stop_count
temperature_case
temperature_celsius
temperature_internal
total_lbas_read
total_lbas_written
total_host_sector_write
udma_crc_error_count
unsafe_shutdown_count
workld_host_reads_perc
workld_media_wear_indic
workload_minutes
SMARTMONATTRS
)"
smartmon_attrs="$(echo ${smartmon_attrs} | xargs | tr ' ' '|')"

parse_smartctl_attributes() {
  local disk="$1"
  local disk_type="$2"
  local name="$3"
  local labels="disk=\"${disk}\",type=\"${disk_type}\",name=\"${name}\""
  local vars="$(echo "${smartmon_attrs}" | xargs | tr ' ' '|')"
  sed 's/^ \+//g' |
    awk -v labels="${labels}" "${parse_smartctl_attributes_awk}" 2>/dev/null |
    grep -E "(${smartmon_attrs})"
}

parse_smartctl_scsi_attributes() {
  local disk="$1"
  local disk_type="$2"
  local name="$3"
  local labels="disk=\"${disk}\",type=\"${disk_type}\",name=\"${name}\""
  while read line; do
    attr_type="$(echo "${line}" | tr '=' ':' | cut -f1 -d: | sed 's/^ \+//g' | tr ' ' '_')"
    attr_value="$(echo "${line}" | tr '=' ':' | cut -f2 -d: | sed 's/^ \+//g')"
    case "${attr_type}" in
    number_of_hours_powered_up_) power_on="$(echo "${attr_value}" | awk '{ printf "%e\n", $1 }')" ;;
    Current_Drive_Temperature) temp_cel="$(echo ${attr_value} | cut -f1 -d' ' | awk '{ printf "%e\n", $1 }')" ;;
    Blocks_read_from_cache_and_sent_to_initiator_) lbas_read="$(echo ${attr_value} | awk '{ printf "%e\n", $1 }')" ;;
    Accumulated_start-stop_cycles) power_cycle="$(echo ${attr_value} | awk '{ printf "%e\n", $1 }')" ;;
    Elements_in_grown_defect_list) grown_defects="$(echo ${attr_value} | awk '{ printf "%e\n", $1 }')" ;;
    Non-medium_error_count) non_medium="$(echo ${attr_value} | awk '{ printf "%e\n", $1 }')" ;;
    read) read_uncorrected="$(echo ${attr_value} | awk '{ printf "%e\n", $7 }')" ;;
    write) write_uncorrected="$(echo ${attr_value} | awk '{ printf "%e\n", $7 }')" ;;
    verify) verify_uncorrected="$(echo ${attr_value} | awk '{ printf "%e\n", $7 }')" ;;
    esac
  done
  [ ! -z "$power_on" ] && echo "power_on_hours_raw_value{${labels},smart_id=\"9\"} ${power_on}"
  [ ! -z "$temp_cel" ] && echo "temperature_celsius_raw_value{${labels},smart_id=\"194\"} ${temp_cel}"
  [ ! -z "$lbas_read" ] && echo "total_lbas_read_raw_value{${labels},smart_id=\"242\"} ${lbas_read}"
  [ ! -z "$power_cycle" ] && echo "power_cycle_count_raw_value{${labels},smart_id=\"12\"} ${power_cycle}"
  [ ! -z "$grown_defects" ] && echo "sas_grown_defects_count_raw_value{${labels},smart_id=\"0\"} ${grown_defects}"
  [ ! -z "$non_medium" ] && echo "sas_non_medium_errors_count_raw_value{${labels},smart_id=\"0\"} ${non_medium}"
  [ ! -z "$read_uncorrected" ] && echo "sas_read_uncorrected_errors_count_raw_value{${labels},smart_id=\"0\"} ${read_uncorrected}"
  [ ! -z "$write_uncorrected" ] && echo "sas_write_uncorrected_errors_count_raw_value{${labels},smart_id=\"0\"} ${write_uncorrected}"
  [ ! -z "$verify_uncorrected" ] && echo "sas_verify_uncorrected_errors_count_raw_value{${labels},smart_id=\"0\"} ${verify_uncorrected}"
}


# NEW
parse_smartctl_cciss_attributes() {
  local disk="$1"
  local disk_type="$2"
  local name="$3"
  local labels="disk=\"${disk}\",type=\"${disk_type}\",name=\"${name}\""

  while read line; do
    attr_type="$(echo "${line}" | tr '=' ':' | cut -f1 -d: | sed 's/^ \+//g' | tr ' ' '_')"
    attr_value="$(echo "${line}" | tr '=' ':' | cut -f2 -d: | sed 's/^ \+//g')"
    ### echo "_DEBUG: " ${attr_type}

    #case "${attr_type}" in
    # Accumulated_power_on_time,_hours) echo "DEBUG xxx: " "$(echo ${attr_value} | awk '{ printf "%e\n", $2}'  )" ;; 
    # Accumulated_power_on_time,_hours) echo "DEBUG xxx: " "$(echo ${attr_value})" ;;
    #esac 

    case "${attr_type}" in
    Percentage_used_endurance_indicator) p_used="$(echo "${attr_value}" | awk '{ printf "%e\n", $1 }')" ;;            # NEW
    Accumulated_power_on_time,_hours) power_on="$(echo "${attr_value}" | awk '{ printf "%e\n", $2 }')" ;;             # NEW "minutes 53364"  hours as float
    ### number_of_hours_powered_up_) power_on="$(echo "${attr_value}" | awk '{ printf "%e\n", $1 }')" ;;
    Current_Drive_Temperature) temp_cel="$(echo ${attr_value} | cut -f1 -d' ' | awk '{ printf "%e\n", $1 }')" ;;      # 2.600000e+01 = 26 C 
    Drive_Trip_Temperature)    trip_cel="$(echo ${attr_value} | cut -f1 -d' ' | awk '{ printf "%e\n", $1 }')" ;;      # NEW maximal drive temperature
    Blocks_read_from_cache_and_sent_to_initiator_) lbas_read="$(echo ${attr_value} | awk '{ printf "%e\n", $1 }')" ;;
    Accumulated_start-stop_cycles) power_cycle="$(echo ${attr_value} | awk '{ printf "%e\n", $1 }')" ;;
    Elements_in_grown_defect_list) grown_defects="$(echo ${attr_value} | awk '{ printf "%e\n", $1 }')" ;;
    Non-medium_error_count) non_medium="$(echo ${attr_value} | awk '{ printf "%e\n", $1 }')" ;;
    read) read_uncorrected="$(echo ${attr_value} | awk '{ printf "%e\n", $7 }')" ;;
    write) write_uncorrected="$(echo ${attr_value} | awk '{ printf "%e\n", $7 }')" ;;
    verify) verify_uncorrected="$(echo ${attr_value} | awk '{ printf "%e\n", $7 }')" ;;
    esac
  done

  [ ! -z "$p_used" ] && echo "percentage_used_endurance_indicator_raw_value{${labels},smart_id=\"0\"} ${p_used}"
  [ ! -z "$power_on" ] && echo "power_on_hours_raw_value{${labels},smart_id=\"9\"} ${power_on}"
  [ ! -z "$temp_cel" ] && echo "temperature_celsius_raw_value{${labels},smart_id=\"194\"} ${temp_cel}"
  [ ! -z "$trip_cel" ] && echo "temperature_celsius_raw_value_trip{${labels},smart_id=\"194\"} ${trip_cel}"           
  [ ! -z "$lbas_read" ] && echo "total_lbas_read_raw_value{${labels},smart_id=\"242\"} ${lbas_read}"
  [ ! -z "$power_cycle" ] && echo "power_cycle_count_raw_value{${labels},smart_id=\"12\"} ${power_cycle}"
  [ ! -z "$grown_defects" ] && echo "sas_grown_defects_count_raw_value{${labels},smart_id=\"0\"} ${grown_defects}"
  [ ! -z "$non_medium" ] && echo "sas_non_medium_errors_count_raw_value{${labels},smart_id=\"0\"} ${non_medium}"
  [ ! -z "$read_uncorrected" ] && echo "sas_read_uncorrected_errors_count_raw_value{${labels},smart_id=\"0\"} ${read_uncorrected}"
  [ ! -z "$write_uncorrected" ] && echo "sas_write_uncorrected_errors_count_raw_value{${labels},smart_id=\"0\"} ${write_uncorrected}"
  [ ! -z "$verify_uncorrected" ] && echo "sas_verify_uncorrected_errors_count_raw_value{${labels},smart_id=\"0\"} ${verify_uncorrected}"
}

# NEW
# Wird benötigt, damit mit "echo ${MANU}" eine einzige Rückgabe erzeugt wird, mit der eine Variable in der gleichen Shell gesetzt werden kann.
# Die Funktion "parse_smartctl_cciss_attributes" kann dafür nicht mitgenutzt werden, da mit deren Ausgaben Metriken erzeugt werden!
parse_year_week() {
  MANU=""
  while read line; do
    attr_type="$(echo "${line}" | tr '=' ':' | cut -f1 -d: | sed 's/^ \+//g' | tr ' ' '_')"
    attr_value="$(echo "${line}" | tr '=' ':' | cut -f2 -d: | sed 's/^ \+//g')"

    case "${attr_type}" in
         Manufactured_in*) manufactured_in="$(echo ${attr_value})" ;;                                  # Manufactured in week 31 of year 2015 
    esac
  done

  [ ! -z "$manufactured_in" ] &&  MANU=$(echo ${manufactured_in} | awk '{ printf "%04d-%02d\n", $7,$4 }')  # 2015-31 or 2019-01

  echo  ${MANU}  # Rückgabewert
}

parse_smartctl_info() {
  local -i smart_available=0 smart_enabled=0 smart_healthy=0
  local disk="$1" disk_type="$2" name="$3"
  local resource_provisioned='N/A' form_factor='N/A' rotation_rate='N/A'  compliance='N/A' model_family='N/A' device_model='N/A' size='N/A' serial_number='N/A' fw_version='N/A' vendor='N/A' product='N/A' revision='N/A' lun_id='N/A'

  while read line; do
    info_type="$(echo "${line}" | cut -f1 -d: | tr ' ' '_')"
    info_value="$(echo "${line}" | cut -f2- -d: | sed 's/^ \+//g' | sed 's/"/\\"/')"
    ### echo "DEBUG xxx :" ${info_type}
    case "${info_type}" in
    Model_Family) model_family="${info_value}" ;;
    Device_Model) device_model="${info_value}" ;;
    Serial_[Nn]umber) serial_number="${info_value}" ;;
    Firmware_Version) fw_version="${info_value}" ;;
    User_Capacity) size="$(echo ${info_value}| sed -E 's/\s+.+$//g' | tr -d ','| awk '{printf "%d GB\n", $1/1024/1024/1024}')" ;;
    Vendor) vendor="${info_value}" ;;
    Product) product="${info_value}" ;;
    Revision) revision="${info_value}" ;;
    Compliance) compliance="${info_value}" ;;       # NEW
    Rotation_Rate) rotation_rate="${info_value}" ;; # NEW
    Form_Factor) form_factor="${info_value}" ;;     # NEW
    LU_is_resource_provisioned*) resource_provisioned="$(echo  ${info_type} | sed -e 's/[LU_is_resource_provisioned,_]//2g'  )" ;; # NEW
    Logical_block_size) size_lb="${info_value}" ;;  # NEW
    Physical_block_size) size_pb="${info_value}" ;; # NEW
    Logical_Unit_id) lun_id="${info_value}" ;;
    esac
    if [[ "${info_type}" == 'SMART_support_is' ]]; then
      case "${info_value:0:7}" in
      Enabled) smart_enabled=1 ;;
      Availab) smart_available=1 ;;
      Unavail) smart_available=0 ;;
      esac
    fi
    if [[ "${info_type}" == 'SMART_overall-health_self-assessment_test_result' ]]; then
      info_value=`echo ${info_value}| tr -d ' '`
      case "${info_value}" in
      PASSED) smart_healthy=1 ;;
      esac
    elif [[ "${info_type}" == 'SMART_Health_Status' ]]; then
      info_value=`echo ${info_value}| tr -d ' '`
      case "${info_value}" in
      OK) smart_healthy=1 ;;
      esac
    fi
  done

  if [[ $device_model == 'N/A' ]] && ([[ $vendor != 'N/A' ]] || [[ $product != 'N/A'  ]])
    then
    device_model="${vendor} $product"
  fi


  # Because in our case it's empty, removed label from metric device_info: ,firmware_version=\"${fw_version}\",model_family=\"${model_family}\",
  echo "device_info{manufactured=\"${var}\",disk=\"${disk}\",type=\"${disk_type}\",name=\"${name}\",vendor=\"${vendor}\",product=\"${product}\",revision=\"${revision}\",lun_id=\"${lun_id}\",device_model=\"${device_model}\",serial_number=\"${serial_number}\",size=\"${size}\",size_pb=\"${size_pb}\",size_lb=\"${size_lb}\",resource_provisioned=\"${resource_provisioned}\",form_factor=\"${form_factor}\",rotation_rate=\"${rotation_rate}\",compliance=\"${compliance}\",smart_healthy=\"${smart_healthy}\"} 1"

  echo "device_smart_available{disk=\"${disk}\",type=\"${disk_type}\",name=\"${name}\"} ${smart_available}"
  echo "device_smart_enabled{disk=\"${disk}\",type=\"${disk_type}\",name=\"${name}\"} ${smart_enabled}"
  echo "device_smart_healthy{disk=\"${disk}\",type=\"${disk_type}\",name=\"${name}\"} ${smart_healthy}"


}

# Here the HELP and TYPE rows are build for each metric
# HELP smartmon_smartctl_run SMART metric smartctl_run
# TYPE smartmon_smartctl_run gauge
# smartmon_smartctl_run{disk="/dev/sda",type="cciss,0",name="HP MM1000JEFRB"} 1643377268
output_format_awk="$(
  cat <<'OUTPUTAWK'
BEGIN { v = "" }
v != $1 {
  print "# HELP smartmon_" $1 " SMART metric " $1;
  print "# TYPE smartmon_" $1 " gauge";
  v = $1
}
{print "smartmon_" $0}
OUTPUTAWK
)"



format_output() {
  sort |
    awk -F'{' "${output_format_awk}"
}

smartctl_version="$(${SMARTCTL} -V | head -n1 | awk '$1 == "smartctl" {print $2}')"
# echo "DEBUG for cron: " $smartctl_version "  " $SMARTCTL
echo "smartctl_version{version=\"${smartctl_version}\"} 1" | format_output

if [[ "$(expr "${smartctl_version}" : '\([0-9]*\)\..*')" -lt 6 ]]; then
  exit
fi

device_list=
if [[ -z $FORCED_DEVICE_LIST ]]
  then
  device_list="$($SMARTCTL --scan-open | awk '/^\/dev/{print $1 "|" $3}')"
else
  device_list=$FORCED_DEVICE_LIST
fi

for device in ${device_list}; do
  disk="$(echo ${device} | cut -f1 -d'|')"
  type="$(echo ${device} | cut -f2 -d'|')"
  active=1

  # Check if the device is in a low-power mode
  $SMARTCTL -n standby -d "${type}" "${disk}" > /dev/null || active=0
  echo "device_active{disk=\"${disk}\",type=\"${type}\"}" "${active}"
  # Skip further metrics to prevent the disk from spinning up
  test ${active} -eq 0 && continue

  # Get Device name label
  name=""
  case ${type} in
    scsi)
      vendor=`$SMARTCTL -i -d "${type}" "${disk}" | awk -F ':' '/Vendor/ {print $2}'| sed -E 's/^\s+//g'`
      product=`$SMARTCTL -i -d "${type}" "${disk}" | awk -F ':' '/Product/ {print $2}'| sed -E 's/^\s+//g'`
      name="${vendor} ${product}" ;;
    *)
      name=`$SMARTCTL -i -d "${type}" "${disk}" | awk -F ':' '/Device Model/ {print $2}'| sed -E 's/^\s+//g'` ;;
  esac

  ## cciss NEW ##
  # Get the SMART attributes for cciss - must be done before: Get the SMART information and health
  # so that year_week information can be passed to: parse_smartctl_info via "${var}"  
  case ${type} in
    cciss*)
      vendor=`$SMARTCTL -i -d "${type}" "${disk}" | awk -F ':' '/Vendor/ {print $2}'| sed -E 's/^\s+//g'`
      product=`$SMARTCTL -i -d "${type}" "${disk}" | awk -F ':' '/Product/ {print $2}'| sed -E 's/^\s+//g'`
      $SMARTCTL -a -d "${type}" "${disk}" | parse_smartctl_cciss_attributes "${disk}" "${type}" "${name}"  # get cciss metrics
      var="$(   $SMARTCTL -a -d "${type}" "${disk}" | parse_year_week   )"   ;;                            # set var with year and week information
      name="${vendor} ${product}" ;;
    *)
      name=`$SMARTCTL -i -d "${type}" "${disk}" | awk -F ':' '/Device Model/ {print $2}'| sed -E 's/^\s+//g'` ;;
  esac

  echo "smartctl_run{disk=\"${disk}\",type=\"${type}\",name=\"${name}\"}" "$(TZ=UTC date '+%s')"

  # Get the SMART information and health - NEW $var
  $SMARTCTL -i -H -d "${type}" "${disk}"  | parse_smartctl_info "${disk}" "${type}" "${name}" "${var}"      # put var in
 
  # Get the SMART attributes
  case ${type} in
    sat) $SMARTCTL -A -d "${type}" "${disk}" | parse_smartctl_attributes "${disk}" "${type}" "${name}" ;;
    atacam) $SMARTCTL -A -d "${type}" "${disk}" | parse_smartctl_attributes "${disk}" "${type}" "${name}" ;;
    sat+megaraid*) $SMARTCTL -A -d "${type}" "${disk}" | parse_smartctl_attributes "${disk}" "${type}" "${name}" ;;
    scsi) $SMARTCTL -a -d "${type}" "${disk}" | parse_smartctl_scsi_attributes "${disk}" "${type}" "${name}" ;;
    megaraid*) $SMARTCTL -A -d "${type}" "${disk}" | parse_smartctl_scsi_attributes "${disk}" "${type}" "${name}" ;;
    *)
      continue
      ;;
  esac
done | format_output
