#!/bin/bash

# file: smartmon.sh
# Added more metric information, cciss and nvme metrics and FORCED_DEVICE_LIST by Michael Hollstein, 2022/01
#
# Script informed by the collectd monitoring script for smartmontools (using smartctl)
# by Samuel B. <samuel_._behan_(at)_dob_._sk> (c) 2012
# source at: http://devel.dob.sk/collectd-scripts/

# TODO: This probably needs to be a little more complex.  The raw numbers can have more
#       data in them than you'd think.
#       http://arstdevice_activeechnica.com/civis/viewtopic.php?p=22062211

# Formatting done via shfmt -i 2
# https://github.com/mvdan/sh

# Run script every 5 minutes
# crontab -e
# # smart_exporter
# */5 * * * * /opt/smart_exporter/do_smartmon.sh 2>&1



SMARTCTL=/usr/sbin/smartctl


# set your own devices
# see also: hpssacli ctrl all show config
FORCED_DEVICE_LIST=$(cat << EOF
/dev/sda|cciss,00
/dev/sda|cciss,01
/dev/sda|cciss,02
/dev/sda|cciss,03
/dev/sde|cciss,04
/dev/sde|cciss,05
/dev/sde|cciss,06
/dev/sde|cciss,07
EOF
)
 
# For nvme devices  
#FORCED_DEVICE_LIST=$(cat << EOF
#/dev/nvme0|nvme
#/dev/nvme1|nvme
#/dev/nvme2|nvme
#/dev/nvme3|nvme
#/dev/nvme4|nvme
#/dev/nvme5|nvme
#/dev/nvme6|nvme
#/dev/nvme7|nvme
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

# NEW nvme
parse_smartctl_nvme_attributes() {
  local disk="$1"
  local disk_type="$2"
  local name="$3"
  local serial_number="$4"
  local labels="disk=\"${disk}\",type=\"${disk_type}\",name=\"${name}\",serial_number=\"${serial_number}\""
  local no_errors_logged=0

   while read line; do
     attr_type="$(echo "${line}" | tr '=' ':' | cut -f1 -d: | sed 's/^ \+//g' | tr ' ' '_')"
     attr_value="$(echo "${line}" | tr '=' ':' | cut -f2 -d: | sed 's/^ \+//g')"
     # echo "_DEBUG:" ${attr_type} '##' ${attr_value}

     case "${attr_type}" in
     # Maximum_Data_Transfer_Size) transfer_size="$( echo "${attr_value}" | awk '{printf "%d\n", $1}' )" ;;
     Temperature) temp_cel="$(echo ${attr_value} | cut -f1 -d' ' | awk '{ printf "%e\n", $1 }')" ;;                                  # 2.600000e+01 = 26 C 
     Available_Spare) spare_available="$(echo ${attr_value} | cut -f1 -d'%' | awk '{ printf "%e\n", $1 }')" ;;
     Available_Spare_Threshold) spare_available_threshold="$(echo ${attr_value} | cut -f1 -d'%' | awk '{ printf "%d\n", $1 }')" ;;
     Warning__Comp\._Temp\._Threshold) temp_warn_cel="$(echo ${attr_value} | cut -f1 -d' ' | awk '{ printf "%e\n", $1 }')" ;;
     Critical_Comp\._Temp\._Threshold) temp_critical_cel="$(echo ${attr_value} | cut -f1 -d' ' | awk '{ printf "%e\n", $1 }')" ;;
     Critical_Warning) critical_warning="$(echo ${attr_value} | awk '{printf "%03d\n", $1}' )" ;;  # hex to decimal 000 ... 016
     #Critical_Warning) critical_warning="$(echo 10 | awk '{printf "%03d\n", $1}' )" ;;  # hex to decimal 000 ... 016
     Controller_Busy_Time) controller_busy="$(echo "${attr_value}" | sed -E '{s/'[,.]'/''/g}' | awk '{ printf "%e\n", $1 }')" ;;
     Power_Cycles) power_cycles="$(echo "${attr_value}" | sed -E '{s/'[,.]'/''/g}' | awk '{ printf "%e\n", $1 }')" ;;
     Power_On_Hours) power_on="$(echo "${attr_value}" | sed -E '{s/'[,.]'/''/g}' | awk '{ printf "%e\n", $1 }')" ;; # replace , and . with nothing. 
     Unsafe_Shutdowns) unsafe_shutdowns="$(echo "${attr_value}" | sed -E '{s/'[,.]'/''/g}' | awk '{ printf "%e\n", $1 }')" ;;
     Media_and_Data_Integrity_Errors) integrity_errors="$(echo "${attr_value}" | sed -E '{s/'[,.]'/''/g}' | awk '{ printf "%e\n", $1 }')" ;;
     Error_Information_Log_Entries) log_entries="$(echo "${attr_value}" | sed -E '{s/'[,.]'/''/g}' | awk '{ printf "%e\n", $1 }')" ;;
     Warning__Comp\._Temperature_Time) warning_temp_time="$(echo "${attr_value}" | sed -E '{s/'[,.]'/''/g}' | awk '{ printf "%e\n", $1 }')" ;;
     Critical_Comp\._Temperature_Time) critical_temp_time="$(echo "${attr_value}" | sed -E '{s/'[,.]'/''/g}' | awk '{ printf "%e\n", $1 }')" ;;
     Temperature_Sensor_1) temperature_sensor_1="$(echo ${attr_value} | cut -f1 -d' ' | awk '{ printf "%e\n", $1 }')" ;;
     Temperature_Sensor_2) temperature_sensor_2="$(echo ${attr_value} | cut -f1 -d' ' | awk '{ printf "%e\n", $1 }')" ;;
     Temperature_Sensor_3) temperature_sensor_3="$(echo ${attr_value} | cut -f1 -d' ' | awk '{ printf "%e\n", $1 }')" ;;
     Error_Information_\(NVMe*) error_information="$(echo ${attr_value} | sed -E  "{s/^Error Information //g}" | tr -d \( | tr -d \) )" ;;
     No_Errors_Logged) no_errors_logged=1 ;;
     esac

   done

   # metric smartmon_ ...             metric names
   if [[ ${no_errors_logged} == 1 ]]
     then
         [ ! -z "$no_errors_logged" ] && echo "no_errors_logged{${labels},smart_id=\"N/A\"} 1"
     else
          [ ! -z "$no_errors_logged" ] && echo "no_errors_logged{${labels},smart_id=\"N/A\"} 0"
   fi
   # now in device_info  [ ! -z "$transfer_size" ] && echo "maximum_data_transfer_size_pages{${labels},smart_id=\"N/A\"} ${transfer_size}"
   [ ! -z "$spare_available" ] && echo "available_spare_percent_raw_value{${labels},smart_id=\"N/A\",avail_spare_threshold=\"${spare_available_threshold}\"} ${spare_available}"
   [ ! -z "$temp_cel" ] && echo "temperature_celsius_raw_value{${labels},smart_id=\"194\"} ${temp_cel}"
   [ ! -z "$temp_warn_cel" ] && echo "temperature_celsius_warn_raw_value{${labels},smart_id=\"194\"} ${temp_warn_cel}"
   [ ! -z "$temp_critical_cel" ] && echo "temperature_celsius_critical_raw_value{${labels},smart_id=\"194\"} ${temp_critical_cel}"
   if [[ $critical_warning -gt 0 ]]
     then
         [ ! -z "$critical_warning" ] && echo "controller_critical_warning{${labels},smart_id=\"N/A\",critical_warning=\"${critical_warning}\"} 0"
     else
         [ ! -z "$critical_warning" ] && echo "controller_critical_warning{${labels},smart_id=\"N/A\",critical_warning=\"${critical_warning}\"} 1"
   fi
   [ ! -z "$controller_busy" ] && echo "controller_busy_time_raw_value{${labels},smart_id=\"N/A\"} ${controller_busy}"
   [ ! -z "$power_cycles" ] && echo "power_cycle_count_raw_value{${labels},smart_id=\"N/A\"} ${power_cycles}"
   [ ! -z "$power_on" ] && echo "power_on_hours_raw_value{${labels},smart_id=\"9\"} ${power_on}"
   [ ! -z "$unsafe_shutdowns" ] && echo "unsafe_shutdowns_raw_value{${labels},smart_id=\"N/A\"} ${unsafe_shutdowns}"
   [ ! -z "$integrity_errors" ] && echo "media_and_data_integrity_errors_raw_value{${labels},smart_id=\"N/A\"} ${integrity_errors}"
   [ ! -z "$log_entries" ] && echo "error_information_log_entries_raw_value{${labels},smart_id=\"N/A\"} ${log_entries}"
   [ ! -z "$warning_temp_time" ] && echo "warning_comp_temperature_time_raw_value{${labels},smart_id=\"194\"} ${warning_temp_time}"
   [ ! -z "$critical_temp_time" ] && echo "critical_comp_temperature_time_raw_value{${labels},smart_id=\"194\"} ${critical_temp_time}"
   [ ! -z "$temperature_sensor_1" ] && echo "temperature_sensor_1_celsius_raw_value{${labels},smart_id=\"194\"} ${temperature_sensor_1}"
   [ ! -z "$temperature_sensor_2" ] && echo "temperature_sensor_2_celsius_raw_value{${labels},smart_id=\"194\"} ${temperature_sensor_2}"
   [ ! -z "$temperature_sensor_3" ] && echo "temperature_sensor_3_celsius_raw_value{${labels},smart_id=\"194\"} ${temperature_sensor_3}"

}
# END nvme

# NEW cciss
parse_smartctl_cciss_attributes() {
  local disk="$1"
  local disk_type="$2"
  local name="$3"
  local serial_number="$4"
  local labels="disk=\"${disk}\",type=\"${disk_type}\",name=\"${name}\",serial_number=\"${serial_number}\""

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
    Accumulated_power_on_time_hours) power_on="$(echo "${attr_value}" | awk '{ printf "%e\n", $2 }')" ;;             # NEW "minutes 53364"  hours as float
    ### number_of_hours_powered_up_) power_on="$(echo "${attr_value}" | awk { printf "%e\n", $1 }')" ;;
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
# END cciss

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

# PCI IDs
parse_pci_ids() {
  PCI=""
  while read line; do
    attr_type="$(echo "${line}" | tr '=' ':' | cut -f1 -d: | sed 's/^ \+//g' | tr ' ' '_')"
    attr_value="$(echo "${line}" | tr '=' ':' | cut -f2 -d: | sed 's/^ \+//g')"

    case "${attr_type}" in
         PCI_Vendor*) pci_ids=`$SMARTCTL -i -d "${type}" "${disk}" | awk -F ':' '/Vendor/ {print $2}'| sed -E 's/^\s+//g'` ;;
    esac
  done
  [ ! -z "$pci_ids" ] &&  PCI=$(echo ${pci_ids})

  echo  ${PCI}  # Rückgabewert
}

# maximum_data_transfer_size_pages
parse_pages() {
  PAGES=""
  while read line; do
    attr_type="$(echo "${line}" | tr '=' ':' | cut -f1 -d: | sed 's/^ \+//g' | tr ' ' '_')"
    attr_value="$(echo "${line}" | tr '=' ':' | cut -f2 -d: | sed 's/^ \+//g')"

    case "${attr_type}" in
         Maximum_Data_Transfer_Size) transfer_size="$( echo "${attr_value}" | awk '{printf "%d\n", $1}' )" ;;
    esac
  done
  [ ! -z "$transfer_size" ] &&  PAGES=$(echo ${transfer_size})

  echo  ${PAGES}  # Rückgabewert
}

# serial_number
parse_serial_number() {
  local serial_number="N/A"

  while read line; do
    info_type="$(echo "${line}" | cut -f1 -d: | tr ' ' '_')"
    info_value="$(echo "${line}" | cut -f2- -d: | sed 's/^ \+//g' | sed 's/"/\\"/')"

    case "${info_type}" in
      Serial_[Nn]umber) serial_number="${info_value}" ;;
    esac
  done

  echo ${serial_number} # Rückgabewert
}

parse_smartctl_info() {
  local -i smart_available=0 smart_enabled=0 smart_healthy=0
  local disk="$1" disk_type="$2" name="$3" vendor_ids="$5" nvme_vendor="$6" transfer_pages="$7"
  local  resource_provisioned='N/A' form_factor='N/A' rotation_rate='N/A'  compliance='N/A' model_family='N/A' device_model='N/A' size='N/A' size_lb='N/A' size_pb='N/A' serial_number='N/A' fw_version='N/A' vendor='N/A' product='N/A' revision='N/A' lun_id='N/A' nvme_version="N/A" disk_type2="N/A"

  while read line; do
    info_type="$(echo "${line}" | cut -f1 -d: | tr ' ' '_')"
    info_value="$(echo "${line}" | cut -f2- -d: | sed 's/^ \+//g' | sed 's/"/\\"/')"
    ### echo "DEBUG xxx :" ${info_type}

    case "${info_type}" in
    Model_Family) model_family="${info_value}" ;;
    Model_Number) device_model="${info_value}"  product='N/A'   ;; # nvme has no Product. Look at device_model instead
    Device_Model) device_model="${info_value}" ;; # cciss
    Serial_[Nn]umber) serial_number="${info_value}" ;;
    Firmware_Version) fw_version="${info_value}" ;;
    # nvme: "1,600,321,314,816 [1.60 TB]"  Result: 1600 GB
    Total_NVM_Capacity) size="$( echo ${info_value} |  sed -E 's/\s+.+$//g' |  sed -E '0,/","/{s/','/''/}' | awk '{printf "%d GB\n", $1}' )" ;; # nvme
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
    NVMe_Version) nvme_version="${info_value}" ;; # nvme
    esac

    # check SMART 
    if [[ "${info_type}" == 'SMART_support_is' ]]; then
      case "${info_value:0:7}" in
      Enabled) smart_enabled=1 ;;
      Availab) smart_available=1 ;;
      Unavail) smart_available=0 ;;
      esac
    elif [[ "${info_type}" == 'SMART_overall-health_self-assessment_test_result' ]] && [[ "${type}" == 'nvme' ]]
       then
       smart_enabled=1
       smart_available=1
    fi

    # SMART Health Status
    if [[ "${info_type}" == 'SMART_overall-health_self-assessment_test_result' ]]; then
      info_value=`echo ${info_value}| tr -d ' '`
      case "${info_value}" in
      PASSED) smart_healthy=1 ;; # valid for nvme
      esac
    elif [[ "${info_type}" == 'SMART_Health_Status' ]]; then
      info_value=`echo ${info_value}| tr -d ' '`
      case "${info_value}" in
      OK) smart_healthy=1 ;;     # valid for cciss
      esac
    fi
  done

  # vendor
  if [[ $nvme_vendor != "" ]] && [[ $vendor == 'N/A' ]]
    then
    vendor="${nvme_vendor}"
  fi
  if [[ $vendor_ids == '' ]]
    then
    vendor_ids='N/A'
  fi

  # device_model
  if [[ $device_model == 'N/A' ]] && ([[ $vendor != 'N/A' ]] || [[ $product != 'N/A'  ]])
    then
    device_model="${vendor} $product"
  fi

  # Because in our case it's empty, removed label from metric device_info: ,firmware_version=\"${fw_version}\",model_family=\"${model_family}\",
  if [[ ${nvme_version} != "N/A" ]]
    then # nvme disk - use disk_type2 as type
      disk_type2="$( echo ${disk} | sed -E  's|/|+|g' | sed -E 's|\+dev\+||g' )" # nvme0...nvmex filtered from disk
      echo "device_info{manufactured=\"${year_week}\",fw_version=\"${fw_version}\",nvme_version=\"${nvme_version}\",disk=\"${disk}\",pages=\"${transfer_pages}\",type=\"${disk_type2}\",name=\"${name}\",vendor=\"${vendor}\",vendor_ids=\"${vendor_ids}\",product=\"${product}\",revision=\"${revision}\",lun_id=\"${lun_id}\",device_model=\"${device_model}\",serial_number=\"${serial_number}\",size=\"${size}\",size_pb=\"${size_pb}\",size_lb=\"${size_lb}\",resource_provisioned=\"${resource_provisioned}\",form_factor=\"${form_factor}\",rotation_rate=\"${rotation_rate}\",compliance=\"${compliance}\",smart_healthy=\"${smart_healthy}\"} 1"

      echo "device_smart_available{disk=\"${disk}\",type=\"${disk_type2}\",name=\"${name}\",serial_number=\"${serial_number}\"} ${smart_available}"
      echo "device_smart_enabled{disk=\"${disk}\",type=\"${disk_type2}\",name=\"${name}\",serial_number=\"${serial_number}\"} ${smart_enabled}"
      echo "device_smart_healthy{disk=\"${disk}\",type=\"${disk_type2}\",name=\"${name}\",serial_number=\"${serial_number}\"} ${smart_healthy}"
    else # not a nvme disk - use disk_type as type
      echo "device_info{manufactured=\"${year_week}\",fw_version=\"${fw_version}\",nvme_version=\"${nvme_version}\",disk=\"${disk}\",pages=\"${transfer_pages}\",type=\"${disk_type}\",name=\"${name}\",vendor=\"${vendor}\",vendor_ids=\"${vendor_ids}\",product=\"${product}\",revision=\"${revision}\",lun_id=\"${lun_id}\",device_model=\"${device_model}\",serial_number=\"${serial_number}\",size=\"${size}\",size_pb=\"${size_pb}\",size_lb=\"${size_lb}\",resource_provisioned=\"${resource_provisioned}\",form_factor=\"${form_factor}\",rotation_rate=\"${rotation_rate}\",compliance=\"${compliance}\",smart_healthy=\"${smart_healthy}\"} 1"

      echo "device_smart_available{disk=\"${disk}\",type=\"${disk_type}\",name=\"${name}\",serial_number=\"${serial_number}\"} ${smart_available}"
      echo "device_smart_enabled{disk=\"${disk}\",type=\"${disk_type}\",name=\"${name}\",serial_number=\"${serial_number}\"} ${smart_enabled}"
      echo "device_smart_healthy{disk=\"${disk}\",type=\"${disk_type}\",name=\"${name}\",serial_number=\"${serial_number}\"} ${smart_healthy}"
  fi

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
  # Build disk and type 
  disk="$(echo ${device} | cut -f1 -d'|')"    # /dev/nvme0 ... /dev/nvmex
  type="$(echo ${device} | cut -f2 -d'|')"    # nvme
  case "${type}" in
          nvme) type2="$(echo "${disk}" | sed -E  's|/|+|g' | sed -E 's|\+dev\+||g')" ;; # nvme0 ... nvmex
  esac
  serial_number="N/A"
  serial_number="$( $SMARTCTL -i -H -d "${type}" "${disk}"  | parse_serial_number )"
  active=1

  # Check if the device is in a low-power mode
  $SMARTCTL -n standby -d "${type}" "${disk}" > /dev/null || active=0
  if [[ ${type} == "nvme" ]]
    then
      echo "device_active{disk=\"${disk}\",type=\"${type2}\",serial_number=\"${serial_number}\"}" "${active}"
    else
      echo "device_active{disk=\"${disk}\",type=\"${type}\",serial_number=\"${serial_number}\"}" "${active}"
  fi
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

  ## NEW HP cciss and nvme ##
  # Get the SMART attributes for cciss and nvme - must be done before: Get the SMART information and health
  # so that year_week information and vendor_ids can be passed to: parse_smartctl_info 
  case ${type} in
    cciss*)
      # serial_number="$( $SMARTCTL -i -H -d "${type}" "${disk}"  | parse_serial_number )"     
      vendor=`$SMARTCTL -i -d "${type}" "${disk}" | awk -F ':' '/Vendor/ {print $2}'| sed -E 's/^\s+//g'`
      product=`$SMARTCTL -i -d "${type}" "${disk}" | awk -F ':' '/Product/ {print $2}'| sed -E 's/^\s+//g'`
      name="${vendor} ${product}"
      $SMARTCTL -a -d "${type}" "${disk}" | parse_smartctl_cciss_attributes "${disk}" "${type}" "${name}" "${serial_number}"   # get cciss metrics
      year_week="$(     $SMARTCTL -a -d "${type}" "${disk}" | parse_year_week   )"                           # set var with year and week information
      transfer_pages="N/A" ;;
    nvme)
      # serial_number="$(   $SMARTCTL -i -H -d "${type}" "${disk}"  | parse_serial_number )"                       # https://www.devicekb.com/en/hardware/pci-vendors
      vendor="HP"                                                                                                # 0x1590 = HEWLETT-PACKARD
      product=`$SMARTCTL -i -d "${type}" "${disk}" | awk -F ':' '/Model Number/ {print $2}'| sed -E 's/^\s+//g'` # MO001600KWVNB
      name="${vendor} ${product}"                                                                                # HP MO001600KWVNB 0x144d 0x1590
      # $SMARTCTL -a -d "${type}" "${disk}" | parse_smartctl_nvme_attributes "${disk}" "${type}" "${name}"       # get nvme metrics
      # type is now nvme0 to nvme7 from disk information /dev/nvme0 to /dev/nvme7
      $SMARTCTL -a -d "${type}" "${disk}" | parse_smartctl_nvme_attributes "${disk}" "${type2}" "${name}" "${serial_number}"       # get nvme metrics
      vendor_ids="$(  $SMARTCTL -a -d "${type}" "${disk}" | parse_pci_ids  )"
      year_week="N/A"
      transfer_pages="$(  $SMARTCTL -a -d "${type}" "${disk}" | parse_pages  )" ;;                               # get Maximum Data Transfer Size
    *)
      name=`$SMARTCTL -i -d "${type}" "${disk}" | awk -F ':' '/Device Model/ {print $2}'| sed -E 's/^\s+//g'` ;; # here, name is overwritten
  esac
  if [[ ${name} == "" ]]
     then
     name='N/A'
  fi

  # Metric: smartmon_smartctl_run
  if [[ ${type} == "nvme" ]]
    then
      echo "smartctl_run{disk=\"${disk}\",type=\"${type2}\",name=\"${name}\",serial_number=\"${serial_number}\"}" "$(TZ=UTC date '+%s')" 
    else
      echo "smartctl_run{disk=\"${disk}\",type=\"${type}\",name=\"${name}\",serial_number=\"${serial_number}\"}" "$(TZ=UTC date '+%s')"
  fi

  # Metric: smartmon_device_info
  # Get the SMART information and health - NEW: put in  $year_week, $vendor_ids, $vendor, $transfer_pages
  # vendor_ids=`$SMARTCTL -i -d "${type}" "${disk}" | awk -F ':' '/Vendor/ {print $2}'| sed -E 's/^\s+//g'` 
  # 0x144d 0x1590 = "PCI Vendor ID" "PCI Vendor Subsystem ID"
  $SMARTCTL -i -H -d "${type}" "${disk}"  | parse_smartctl_info "${disk}" "${type}" "${name}" "${year_week}" "${vendor_ids}" "${vendor}" "${transfer_pages}"


  # Get the SMART attributes, for other than HP cciss or nvme
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
