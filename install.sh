#!/bin/bash

set -e

GITREPO=https://github.com/UWIT-IAM/amazon-cloudwatch-installer
BASEDIR=/data/aws/amazon-cloudwatch
CREDENTIAL_FILE=/data/local/etc/amazon-cloudwatch-credentials
FILES=(
    /logs/identity-uw/process.log
    /logs/identity-uw/audit.log
    /logs/access_log
    /logs/error_log
)
FILES_CHANGED=
ADDCRON=
NO_RESTART=


install_cloudwatch() {
    mkdir -p $BASEDIR
    pushd $BASEDIR
    BASEDIR=`pwd`
    echo Installing amazon-cloudwatch to $BASEDIR
    mkdir -p temp-install
    pushd temp-install
    curl https://s3.amazonaws.com/amazoncloudwatch-agent/linux/amd64/latest/AmazonCloudWatchAgent.zip > AmazonCloudWatchAgent.zip
    unzip AmazonCloudWatchAgent.zip
    rpm2cpio amazon-cloudwatch-agent.rpm | cpio -idmv
    genconfig > amazon-cloudwatch.toml
    geninit > init.sh && chmod +x init.sh
    cp -p opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent .
    cp -p opt/aws/amazon-cloudwatch-agent/bin/CWAGENT_VERSION .
    popd
    for file in amazon-cloudwatch-agent CWAGENT_VERSION amazon-cloudwatch.toml init.sh; do
	if ! diff -q temp-install/$file $file; then
	    cp -p temp-install/$file .
	    FILES_CHANGED=1
	fi
    done
    rm -rf temp-install
    popd
}

genconfig() {
    local file
    local hostname=`hostname`
    local servername=$(grep -m 1 ServerName /usr/local/apache/conf/host.conf | awk '{ print $2 }' || hostname)
    cat <<-EOF
	[agent]
	  collection_jitter = "0s"
	  debug = false
	  flush_interval = "1s"
	  flush_jitter = "0s"
	  hostname = ""
	  interval = "60s"
	  logfile = "${BASEDIR}/log/amazon-cloudwatch-agent.log"
	  metric_batch_size = 1000
	  metric_buffer_limit = 10000
	  omit_hostname = false
	  precision = ""
	  quiet = false
	  round_interval = false
	
	[inputs]
	
	  [[inputs.cpu]]
	    fieldpass = ["usage_idle"]
	    interval = "60s"
	    percpu = true
	    totalcpu = true
	
	  [[inputs.disk]]
	    fieldpass = ["used_percent"]
	    interval = "60s"
	
	  [[inputs.diskio]]
	    fieldpass = ["write_bytes", "read_bytes", "writes", "reads"]
	    interval = "60s"
	    report_deltas = true
	
	  [[inputs.mem]]
	    fieldpass = ["used_percent"]
	    interval = "60s"
	
	  [[inputs.net]]
	    fieldpass = ["bytes_sent", "bytes_recv", "packets_sent", "packets_recv"]
	    interval = "60s"
	    report_deltas = true
	
	  [[inputs.swap]]
	    fieldpass = ["used_percent"]
	    interval = "60s"
	
	  [[inputs.tail]]
	    data_format = "value"
	    data_type = "string"
	    file_state_folder = "${BASEDIR}/log/state"
	    name_override = "raw_log_line"
	
	EOF
    for file in ${FILES[@]} ; do
    local filename=${file##*/}
    cat <<-EOF
	    [[inputs.tail.file_config]]
	      file_path = "${file}"
	      from_beginning = true
	      log_group_name = "${servername}"
	      log_stream_name = "${hostname}-${filename}"
	      pipe = false
	
EOF
    done
    cat <<-EOF
	[outputs]
	
	  [[outputs.cloudwatch]]
	    force_flush_interval = "60s"
	    namespace = "CWAgent"
	    profile = "AmazonCloudWatchAgent"
	    region = "us-west-2"
	    shared_credential_file = "${CREDENTIAL_FILE}"
	    [outputs.cloudwatch.tagdrop]
	      log_group_name = ["*"]
	
	  [[outputs.cloudwatchlogs]]
	    file_name_field_key = "file_name"
	    file_state_folder = "${BASEDIR}/log/state"
	    force_flush_interval = "5s"
	    log_entry_field_key = "value"
	    log_group_name_tag_key = "log_group_name"
	    log_stream_name = "i-00000b38"
	    log_stream_name_tag_key = "log_stream_name"
	    log_timestamp_field_key = "log_timestamp"
	    multi_line_start_field_key = "multi_line_start"
	    offset_field_key = "offset"
	    profile = "AmazonCloudWatchAgent"
	    region = "us-west-2"
	    shared_credential_file = "${CREDENTIAL_FILE}"
	EOF
}

geninit() {
    cat <<-EOF
	#!/bin/bash
	
	set -e
	
	PIDFILE="${BASEDIR}/amazon-cloudwatch-agent.pid"
	CONFIG="${BASEDIR}/amazon-cloudwatch.toml"
	
	start() {
	    if status >& /dev/null ; then
	        echo "We're already running"
	        return 1
	    fi
	    if [[ ! -r ${CREDENTIAL_FILE} ]] ; then
	        echo "${CREDENTIAL_FILE} access error. Not starting."
	        return 1
	    fi
	
	    echo "Starting amazon-cloudwatch-agent"
	    nohup ${BASEDIR}/amazon-cloudwatch-agent -pidfile \${PIDFILE} -config \${CONFIG} >& /dev/null &
	}
	
	status() {
	    if [ -f \$PIDFILE ] && ps p \$(cat \$PIDFILE) >& /dev/null ; then
	        echo "amazon-cloudwatch-agent is running"
		return 0
	    fi
	    echo "amazon-cloudwatch-agent is NOT running"
	    return 1
	}
	
	stop() {
	    if ! status >& /dev/null ; then
	    echo "We're already stopped"
	    return 1
	    fi
	    kill \$(cat \${PIDFILE})
	    echo "Stopped amazon-cloudwatch-agent"
	}
	
	restart() {
	    stop || true
	    start
	}
	
	case "\$1" in
	    start|status|stop|restart)
	        "\$1"
	        ;;
	    *)
	        echo >&2 "usage: \$0 [start|status|stop|restart]"
	        exit 1
	        ;;
	esac
	EOF
}

addcron() {
    local cronline="@reboot $BASEDIR/init.sh start"
    if crontab -l || true | grep "$cronline" ; then
	echo "We're already in the crontab."
	return 0
    fi
    local tfile=$(mktemp)
    local update_time=`date`
    crontab -l || true > $tfile
    cat <<-EOF >> $tfile
	
	# Added by ${GITREPO} on ${update_time}
	${cronline}
	
	EOF
    crontab $tfile
    rm $tfile
    echo "We've added \"${cronline}\" to $(whoami)'s crontab"
}

absolute_path() {
    local relative_file=shift
    echo "$(cd "$(dirname "$1")"; pwd)/$(basename "$1")"
}

usage() {
    echo >&2 "usage: $0 [--help] [--add-cron] [--restart] [--credentials file] [target_directory]"
    return 1
}

OPT_BASEDIR=
while [[ $# -gt 0 ]]; do
    case $1 in
	--help)
	    usage || true
	    exit 0
	    ;;
	--add-cron)
	    ADDCRON=1
	    shift
	    ;;
	--no-restart)
	    NO_RESTART=1
	    shift
	    ;;
	--credentials)
	    CREDENTIAL_FILE=$(absolute_path $2)
	    shift
	    shift
	    ;;
	*)
	    if [ $OPT_BASEDIR ]; then
		usage
	    fi
	    OPT_BASEDIR=$1
	    BASEDIR=$1
	    shift
	    ;;
    esac
done

install_cloudwatch

if [ $FILES_CHANGED -a ! $NO_RESTART ]; then
    pushd $BASEDIR
    ./init.sh restart
fi

if [ $ADDCRON ] ; then
    addcron
fi