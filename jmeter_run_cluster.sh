#!/bin/bash +x

# Scenario name is a prefix added to the log files. Therefore add something meaningful so that you can track the
# output easily. Eg: saml_redirect_binding.
scenario=$1

# Location of the JMeter script.
script_location=$2

usage_msg="Usage: ./jmeter_run_all.sh <scenario_name> <jmeter_script_location>"
usage_sample="Sample: ./jmeter_run_all.sh saml_redirect_binding /home/ubuntu/scripts/is_540_scripts/saml/SAML2-SSO-RedirectBinding.jmx"

# Sanity check
if [ -z "$1" ]
  then
  	echo "Please add a scenario name for the current test. Eg: saml_redirect_binding"
	echo "$usage_msg"
	echo "$usage_sample"
	exit
fi

if [ -z "$2" ]
  then
    echo "Please provide a valid JMeter script location."
	echo "$usage_msg"
    echo "$usage_sample"
	exit
fi

# In seconds - 10800 = 3hours
time_to_run=30

is_host_1="192.168.57.183"
is_host_2="192.168.57.184"
is_host_1_username="ubuntu"
is_host_2_username="ubuntu"

# General parameters.
carbon_home_1="/home/ubuntu/is-node-1/wso2is-5.5.0"
carbon_home_2="/home/ubuntu/is-node-2/wso2is-5.5.0"
java_home="/usr/lib/jvm/java-8-oracle"
jmeter_home="/home/ubuntu/jmeter-node/apache-jmeter-3.2"
private_key_path="/home/ubuntu/jmeter-node/is-perf.pem"
output_home="/home/ubuntu/jmeter-node/results"

# Used to clean the identity database after each run.
identity_db_host="192.168.57.186"
identity_db_username="root"
identity_db_password="mysql"
identity_db_name="identitydb"

output_directory=$output_home/$scenario
mkdir -p "$output_directory"

echo "************************ Start Performance test for $scenario using script: $script_location ***************************************"

concurrencies=(100 200 300 400 500)

for concurrency in "${concurrencies[@]}"
do
	echo "=========================== CONCURRENCY LEVEL: $concurrency started ============================"

#	echo "Cleaning the identity database....."
#	mysql -u $identity_db_username -p$identity_db_password -h $identity_db_host $identity_db_name < ./setup/clean-database.sql

	echo "Initial MySQLSlap..."
	sudo mysqlslap --user=$identity_db_username --password=$identity_db_password --host=$identity_db_host --concurrency=50 --iterations=10 --auto-generate-sql --verbose >> "$output_directory"/mySQLSlap_"$concurrency".log

#	echo "Cleaning up IS host 1..."
#	ssh -i $private_key_path $is_host_1_username@$is_host_1 << ENDSSH
#        # cleanup any prev session files
#        rm -f $carbon_home_1/repository/logs/gc_log_$scenario$concurrency.log
#        rm -f ~/sar_$scenario$concurrency.log
#
#        echo "Killing All Carbon Servers......"
#        killall java
#        export JAVA_HOME=$java_home
#        export PATH=$JAVA_HOME/bin:$PATH
#
#        echo "********* restarting sysstat ***************"
#        sudo service sysstat restart
#
#        echo "************** starting identity server ***************"
#        sh $carbon_home_1/bin/wso2server.sh restart
#        sleep 100
#
#        echo "************** finished starting identity server *******************"
#        exit
#ENDSSH
#    echo "Cleaning up IS host 2..."
#    ssh -i $private_key_path $is_host_2_username@$is_host_2 << ENDSSH
#        # cleanup any prev session files
#        rm -f $carbon_home_2/repository/logs/gc_log_$scenario$concurrency.log
#        rm -f ~/sar_$scenario$concurrency.log
#
#        echo "Killing All Carbon Servers......"
#        killall java
#    	export JAVA_HOME=$java_home
#    	export PATH=$JAVA_HOME/bin:$PATH
#
#    	echo "********* restarting sysstat ***************"
#    	sudo service sysstat restart
#
#    	echo "************** starting identity server ***************"
#    	sh $carbon_home_2/bin/wso2server.sh restart
#    	sleep 100
#
#    	echo "************** finished starting identity server *******************"
#    	exit
#ENDSSH
#	echo "Ended SSH to IS nodes."

	echo "Starting JMeter run..."
	$jmeter_home/bin/jmeter -Jconcurrency=$concurrency -Jtime=$time_to_run -n -t $script_location -l $output_directory/log_$concurrency.jtl

	echo "MySQLSlap at the end of the current concurrency run..."
	sudo mysqlslap --user=$identity_db_username --password=$identity_db_password --host=$identity_db_host --concurrency=50 --iterations=10 --auto-generate-sql --verbose >> "$output_directory"/mySQLSlap_"$concurrency".log

	ssh -i $private_key_path $is_host_1_username@$is_host_1 << ENDSSH2
        echo "************************"
        mv "$carbon_home_1"/repository/logs/gc.log "$carbon_home_1"/repository/logs/gc_log_"$scenario""$concurrency".log
        touch "$carbon_home_1"/repository/logs/gc.log
        sar -q > sar_$scenario$concurrency.log

#        echo "Killing All Carbon Servers......"
#        killall java
        exit
ENDSSH2

	ssh -i $private_key_path $is_host_2_username@$is_host_2 << ENDSSH2
        echo "************************"
        mv "$carbon_home_2"/repository/logs/gc.log "$carbon_home_2"/repository/logs/gc_log_"$scenario""$concurrency".log
        touch "$carbon_home_2"/repository/logs/gc.log
        sar -q > sar_$scenario$concurrency.log

#        echo "Killing All Carbon Servers......"
#        killall java
        exit
ENDSSH2

	echo "Copying GC logs from IS host 1...."
	scp -i $private_key_path $is_host_1_username@$is_host_1:$carbon_home_1/repository/logs/gc_log_$scenario$concurrency.log $output_directory/host_1_gc_log_$concurrency.log
	echo "Copying GC logs from IS host 2...."
	scp -i $private_key_path $is_host_2_username@$is_host_2:$carbon_home_2/repository/logs/gc_log_$scenario$concurrency.log $output_directory/host_2_gc_log_$concurrency.log

	echo "Copying SAR logs from IS host 1...."
	scp -i $private_key_path $is_host_1_username@$is_host_1:~/sar_$scenario$concurrency.log $output_directory/host_1_sar_log_$concurrency.log
    echo "Copying SAR logs from IS host 2...."
	scp -i $private_key_path $is_host_2_username@$is_host_2:~/sar_$scenario$concurrency.log $output_directory/host_2_sar_log_$concurrency.log

	echo "=========================== CONCURRENCY LEVEL: $concurrency ended ============================"
done
echo "************************ End Performance test for $scenario using script: $script_location ***************************************"
