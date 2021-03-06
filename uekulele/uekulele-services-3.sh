#!/bin/bash

#    Copyright 2015-2019 Gilbert Standen
#    This file is part of Orabuntu-LXC.

#    Orabuntu-LXC is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.

#    Orabuntu-LXC is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.

#    You should have received a copy of the GNU General Public License
#    along with Orabuntu-LXC.  If not, see <http://www.gnu.org/licenses/>.

#    v2.4 		GLS 20151224
#    v2.8 		GLS 20151231
#    v3.0 		GLS 20160710 Updates for Ubuntu 16.04
#    v4.0 		GLS 20161025 DNS DHCP services moved into an LXC container
#    v5.0 		GLS 20170909 Orabuntu-LXC Multi-Host
#    v6.0-AMIDE-beta	GLS 20180106 Orabuntu-LXC AmazonS3 Multi-Host Docker Enterprise Edition (AMIDE)

#    Note that this software builds a containerized DNS DHCP solution (bind9 / isc-dhcp-server).
#    The nameserver should NOT be the name of an EXISTING nameserver but an arbitrary name because this software is CREATING a new LXC-containerized nameserver.
#    The domain names can be arbitrary fictional names or they can be a domain that you actually own and operate.
#    There are two domains and two networks because the "seed" LXC containers are on a separate network from the production LXC containers.
#    If the domain is an actual domain, you will need to change the subnet using the subnets feature of Orabuntu-LXC
#
#!/bin/bash

clear

MajorRelease=$1
OracleRelease=$1$2
OracleVersion=$1.$2
Domain2=$3
MultiHost=$4
DistDir=$5
Product=$6

echo ''
echo "=============================================="
echo "Script:  uekulele-services-3.sh                 "
echo "                                              "
echo "This script installs packages into the Oracle "
echo "Linux container required for running Oracle.  "
echo "=============================================="
echo ''
echo "=============================================="
echo "This script is re-runnable                    "
echo "=============================================="

function GetMultiHostVar2 {
        echo $MultiHost | cut -f2 -d':'
}
MultiHostVar2=$(GetMultiHostVar2)

function GetMultiHostVar4 {
        echo $MultiHost | cut -f4 -d':'
}
MultiHostVar4=$(GetMultiHostVar4)

function GetMultiHostVar7 {
        echo $MultiHost | cut -f7 -d':'
}
MultiHostVar7=$(GetMultiHostVar7)

GetLinuxFlavors(){
if   [[ -e /etc/oracle-release ]]
then
        LinuxFlavors=$(cat /etc/oracle-release | cut -f1 -d' ')
elif [[ -e /etc/redhat-release ]]
then
        LinuxFlavors=$(cat /etc/redhat-release | cut -f1 -d' ')
elif [[ -e /usr/bin/lsb_release ]]
then
        LinuxFlavors=$(lsb_release -d | awk -F ':' '{print $2}' | cut -f1 -d' ')
elif [[ -e /etc/issue ]]
then
        LinuxFlavors=$(cat /etc/issue | cut -f1 -d' ')
else
        LinuxFlavors=$(cat /proc/version | cut -f1 -d' ')
fi
}
GetLinuxFlavors

function TrimLinuxFlavors {
echo $LinuxFlavors | sed 's/^[ \t]//;s/[ \t]$//'
}
LinuxFlavor=$(TrimLinuxFlavors)

if   [ $LinuxFlavor = 'Oracle' ]
then
	CutIndex=7
        function GetRedHatVersion {
                sudo cat /etc/redhat-release | cut -f"$CutIndex" -d' ' | cut -f1 -d'.'
        }
        RedHatVersion=$(GetRedHatVersion)
	RHV=$RedHatVersion
        function GetOracleDistroRelease {
                sudo cat /etc/oracle-release | cut -f5 -d' ' | cut -f1 -d'.'
        }
        OracleDistroRelease=$(GetOracleDistroRelease)
        Release=$OracleDistroRelease
        LF=$LinuxFlavor
        RL=$Release
elif [ $LinuxFlavor = 'Red' ] || [ $LinuxFlavor = 'CentOS' ]
then
        if   [ $LinuxFlavor = 'Red' ]
        then
                function GetRedHatVersion {
                        sudo cat /etc/redhat-release | cut -f7 -d' ' | cut -f1 -d'.'
                }
                RedHatVersion=$(GetRedHatVersion)
        elif [ $LinuxFlavor = 'CentOS' ]
        then
                function GetRedHatVersion {
                        cat /etc/redhat-release | sed 's/ Linux//' | cut -f1 -d'.' | rev | cut -f1 -d' '
                }
                RedHatVersion=$(GetRedHatVersion)
        fi
	RHV=$RedHatVersion
        Release=$RedHatVersion
        LF=$LinuxFlavor
        RL=$Release
elif [ $LinuxFlavor = 'Fedora' ]
then
        CutIndex=3
        function GetRedHatVersion {
                sudo cat /etc/redhat-release | cut -f"$CutIndex" -d' ' | cut -f1 -d'.'
        }
        RedHatVersion=$(GetRedHatVersion)
	RHV=$RedHatVersion
        if [ $RedHatVersion -ge 19 ]
        then
                Release=7
        elif [ $RedHatVersion -ge 12 ] && [ $RedHatVersion -le 18 ]
        then
                Release=6
        fi
        LF=$LinuxFlavor
        RL=$Release
elif [ $LinuxFlavor = 'Ubuntu' ]
then
        function GetUbuntuVersion {
                cat /etc/lsb-release | grep DISTRIB_RELEASE | cut -f2 -d'='
        }
        UbuntuVersion=$(GetUbuntuVersion)
        LF=$LinuxFlavor
        RL=$UbuntuVersion
        function GetUbuntuMajorVersion {
                cat /etc/lsb-release | grep DISTRIB_RELEASE | cut -f2 -d'=' | cut -f1 -d'.'
        }
        UbuntuMajorVersion=$(GetUbuntuMajorVersion)
fi

sleep 5

clear

echo ''
echo "=============================================="
echo "Establish sudo privileges...                  "
echo "=============================================="
echo ''

echo $MultiHostVar4 | sudo -S date

echo ''
echo "=============================================="
echo "Privileges established.                       "
echo "=============================================="

sleep 5

clear

function SoftwareVersion { echo "$@" | awk -F. '{ printf("%d%03d%03d%03d\n", $1,$2,$3,$4); }'; }

function GetLXCVersion {
        lxc-create --version
}
LXCVersion=$(GetLXCVersion)

function CheckSystemdResolvedInstalled {
                sudo netstat -ulnp | grep 53 | sed 's/  */ /g' | rev | cut -f1 -d'/' | rev | sort -u | grep systemd- | wc -l
        }
SystemdResolvedInstalled=$(CheckSystemdResolvedInstalled)

sleep 5

clear
echo ''
echo "=============================================="
echo "Ping yum.oracle.com test...               "
echo "=============================================="
echo ''

ping -c 3 yum.oracle.com

function CheckNetworkUp {
	ping -c 3 yum.oracle.com | grep packet | cut -f3 -d',' | sed 's/ //g'
}
NetworkUp=$(CheckNetworkUp)
n=1
while [ "$NetworkUp" !=  "0%packetloss" ] && [ "$n" -le 5 ]
do
NetworkUp=$(CheckNetworkUp)
n=$((n+1))
done

if [ "$NetworkUp" != '0%packetloss' ]
then
echo ''
echo "=============================================="
echo "Ping yum.oracle.com not reliable.                 "
echo "Script exiting.                               "
echo "=============================================="
exit
else
echo ''
echo "=============================================="
echo "Ping google.com is reliable.                  "
echo "=============================================="
echo ''
fi

sleep 5

clear

echo ''
echo "=============================================="
echo "Initialize LXC Seed Container on OpenvSwitch.."
echo "=============================================="

cd /etc/network/if-up.d/openvswitch

# GLS 20151222 I don't think this step does anything anymore.  Commenting for now, removal pending.
# sudo sed -i "s/lxcora01/oel$OracleRelease$SeedPostfix/" /var/lib/lxc/oel$OracleRelease$SeedPostfix/config

function GetSeedPostfix {
	sudo lxc-ls -f | grep oel"$OracleRelease"c | cut -f1 -d' ' | cut -f2 -d'c' | sed 's/^/c/'
}
SeedPostfix=$(GetSeedPostfix)

function CheckContainerUp {
	sudo lxc-ls -f | grep oel$OracleRelease | sed 's/  */ /g' | egrep 'RUNNING|STOPPED'  | cut -f2 -d' '
}
ContainerUp=$(CheckContainerUp)

function CheckPublicIP {
	sudo lxc-info -n oel$OracleRelease$SeedPostfix -iH | cut -f1-3 -d'.' | sed 's/\.//g'
}
PublicIP=$(CheckPublicIP)

function GetSeedContainerName {
	sudo lxc-ls -f | grep oel$OracleRelease | cut -f1 -d' '	
}
SeedContainerName=$(GetSeedContainerName)

echo ''
echo "=============================================="
echo "Starting LXC Seed Container for Oracle        "
echo "=============================================="
echo ''

if [ $ContainerUp != 'RUNNING' ] || [ $PublicIP != 1020729 ]
then
	function CheckContainersExist {
		sudo ls /var/lib/lxc | grep oel$OracleRelease | sort -V | sed 's/$/ /' | tr -d '\n' | sed 's/^[ \t]*//;s/[ \t]*$//'
	}
	ContainersExist=$(CheckContainersExist)

	function GetSeedContainerName {
		sudo lxc-ls -f | grep oel$OracleRelease | cut -f1 -d' '	
	}
	SeedContainerName=$(GetSeedContainerName)

	sleep 5

        for j in $ContainersExist
        do
		echo "=============================================="
		echo "Display LXC Seed Container Name...            "
		echo "=============================================="
		echo ''
		echo $j
		echo ''
		echo "=============================================="
		echo "Done: Display LXC Seed Container Name.        "
		echo "=============================================="
		echo ''

		sleep 5

                # GLS 20160707 updated to use lxc-copy instead of lxc-clone for Ubuntu 16.04
                # GLS 20160707 continues to use lxc-clone for Ubuntu 15.04 and 15.10

		RedHatVersion=$(GetRedHatVersion)
                
                if [ $Release -eq 7 ] || [ $Release -eq 6 ]
                then
                	function CheckPublicIPIterative {
				sudo lxc-info -n oel$OracleRelease$SeedPostfix -iH | cut -f1-3 -d'.' | sed 's/\.//g'
                	}
                fi
		PublicIPIterative=$(CheckPublicIPIterative)
		echo "Starting container $j ..."
		echo ''
		if [ $MultiHostVar2 = 'Y' ]
		then
			sudo sed -i "s/MtuSetting/$MultiHostVar7/g" /var/lib/lxc/$j/config
		fi
		sudo lxc-start -n $j > /dev/null 2>&1
		i=1
		while [ "$PublicIPIterative" != 1020729 ] && [ "$i" -le 10 ]
		do
			echo "Waiting for $j Public IP to come up..."
			echo ''
			sleep 5
			PublicIPIterative=$(CheckPublicIPIterative)
			if [ $i -eq 5 ]
			then
				echo ''
                                if [ $LinuxFlavor = 'CentOS' ] && [ $Release -eq 6 ]
                                then
                                        sudo lxc-stop -n $j -k > /dev/null 2>&1
                                else
                                        sudo lxc-stop -n $j    > /dev/null 2>&1
                                fi
				sudo /etc/network/openvswitch/veth_cleanups.sh $SeedContainerName
				echo ''
				if [ $MultiHostVar2 = 'Y' ]
				then
					ls -l /var/lib/lxc/$j/config
					sudo sed -i "s/MtuSetting/$MultiHostVar7/g" /var/lib/lxc/$j/config
				fi
				sudo lxc-start -n $j > /dev/null 2>&1
			fi
		sleep 1
		i=$((i+1))
		done
	done
	echo "=============================================="
	echo "LXC Seed Container for Oracle started.        "
	echo "=============================================="
	echo ''
	echo "=============================================="
	echo "Waiting for final container initialization.   " 
	echo "=============================================="
fi

echo ''
echo "==============================================" 
echo "Public IP is up on $SeedContainerName         "
echo ''
sudo lxc-ls -f
echo ''
echo "=============================================="
echo "Container Up.                                 "
echo "=============================================="

sleep 5

clear

echo ''
echo "=============================================="
echo "Container $SeedContainerName ping test...     "
echo "=============================================="
echo ''

function GetDhcpRange {
	cat /etc/sysconfig/lxc-net | grep LXC_DHCP_RANGE | cut -f2 -d'=' | sed 's/"//g' 
}
DhcpRange=$(GetDhcpRange)
DHR="$DhcpRange"
sudo sed -i "s/DHCP-RANGE-OLXC/dhcp-range=$DHR/" /etc/dnsmasq.conf

if [ $Release -ge 7 ]
then
	sudo systemctl daemon-reload
fi

sudo service lxc-net restart > /dev/null 2>&1

ping -c 3 $SeedContainerName

function CheckNetworkUp {
ping -c 3 $SeedContainerName | grep packet | cut -f3 -d',' | sed 's/ //g'
}
NetworkUp=$(CheckNetworkUp)
n=1
while [ "$NetworkUp" !=  "0%packetloss" ] && [ "$n" -le 5 ]
do
NetworkUp=$(CheckNetworkUp)
n=$((n+1))
done

if [ "$NetworkUp" != '0%packetloss' ]
then
	echo ''
	echo "=============================================="
	echo "Container $SeedContainerName not pingable.    "
	echo "Script exiting.                               "
	echo "=============================================="
else
	echo ''
	echo "=============================================="
	echo "Container $SeedContainerName is pingable.     "
	echo "=============================================="
	echo ''
fi

sleep 5

clear

echo ''
echo "=============================================="
echo "Establish sudo privileges...                  "
echo "=============================================="
echo ''

echo $MultiHostVar4 | sudo -S date

echo ''
echo "=============================================="
echo "Privileges established.                       "
echo "=============================================="

sleep 5

clear

echo ''
echo "=============================================="
echo "Testing connectivity to $SeedContainerName... "
echo "=============================================="
echo ''
echo "=============================================="
echo "Output of 'uname -a' in $SeedContainerName... "
echo "=============================================="
echo ''

sudo lxc-attach -n $SeedContainerName -- uname -a
if [ $? -ne 0 ]
then
	echo ''
	echo "=============================================="
	echo "lxc-attach to $SeedContainerName as issue.    "
	echo "lxc-attach to $SeedContainerName must succeed."
	echo "Fix issues retry script.                      "
	echo "Script exiting.                               "
	echo "=============================================="
	exit
else
	# GLS 20180204 Make sure MTU is set correctly in container.

	if [ $MultiHostVar2 = 'Y' ]
	then
		sudo lxc-attach -n $SeedContainerName -- ip link set eth0 mtu $MultiHostVar7
	fi

	echo ''
	echo "=============================================="
	echo "lxc-attach $SeedContainerName successful.     "
	echo "=============================================="
	echo ''
fi

sleep 5

clear

# echo ''
# echo "=============================================="
# echo "Configuring $SeedContainerName for Oracle...  "
# echo "=============================================="
# echo ''
# echo "=============================================="
# echo "Note: sendmail install takes awhile (patience)"
# echo "The install may seem to hang at sendmail...   "
# echo "Give it a minute or two...it's working        "
# echo "=============================================="
# echo ''

# sleep 5

# sudo lxc-attach -n $SeedContainerName -- /root/packages.sh
# sudo lxc-attach -n $SeedContainerName -- /root/create_users.sh
# sudo lxc-attach -n $SeedContainerName -- /root/lxc-services.sh
# sudo lxc-attach -n $SeedContainerName -- usermod --password `perl -e "print crypt('grid','grid');"` grid
# sudo lxc-attach -n $SeedContainerName -- usermod --password `perl -e "print crypt('oracle','oracle');"` oracle
# sudo lxc-attach -n $SeedContainerName -- usermod -g oinstall oracle
# sudo lxc-attach -n $SeedContainerName -- chown oracle:oinstall /home/oracle/.bash_profile
# sudo lxc-attach -n $SeedContainerName -- chown oracle:oinstall /home/oracle/.bashrc
# sudo lxc-attach -n $SeedContainerName -- chown oracle:oinstall /home/oracle/.kshrc
# sudo lxc-attach -n $SeedContainerName -- chown oracle:oinstall /home/oracle/.bash_logout
# sudo lxc-attach -n $SeedContainerName -- chown oracle:oinstall /home/oracle/.
# sudo lxc-attach -n $SeedContainerName -- chown grid:oinstall /home/grid/.bash_profile
# sudo lxc-attach -n $SeedContainerName -- chown grid:oinstall /home/grid/.bashrc
# sudo lxc-attach -n $SeedContainerName -- chown grid:oinstall /home/grid/.kshrc
# sudo lxc-attach -n $SeedContainerName -- chown grid:oinstall /home/grid/.bash_logout
# sudo lxc-attach -n $SeedContainerName -- chown grid:oinstall /home/grid/.

# echo ''  
# echo "=============================================="
# echo "$SeedContainerName configured for Oracle.     "
# echo "=============================================="
# echo ''

# sleep 5

# clear

# if [ $MajorRelease -eq 7 ]
# then
# 	echo ''
# 	echo "=============================================="
# 	echo "Start NTP service...                          "
# 	echo "=============================================="
# 	echo ''

#  	sudo lxc-attach -n $SeedContainerName -- ntpd -x

# 	sudo lxc-attach -n $SeedContainerName -- ntpd -x
# 	sudo lxc-attach -n $SeedContainerName -- chmod +x /etc/systemd/system/ntp.service
# 	sudo lxc-attach -n $SeedContainerName -- systemctl enable ntp.service
# 	sudo lxc-attach -n $SeedContainerName -- service ntp start
# 	sudo lxc-attach -n $SeedContainerName -- service ntpd start
#	sudo lxc-attach -n $SeedContainerName -- service ntp status
# 	sudo lxc-attach -n $SeedContainerName -- chkconfig ntp on
# 	sudo lxc-attach -n $SeedContainerName -- chkconfig ntpd on

#	sleep 5

#	clear

# 	echo ''
# 	echo "=============================================="
# 	echo "Done: Start NTP service.                      "
# 	echo "=============================================="

# 	sleep 5

# 	clear
# elif [ $MajorRelease -eq 6 ] || [ $MajorRelease -eq 5 ]
# then
# 	sudo lxc-attach -n $SeedContainerName -- ntpd -x
# fi

sleep 5

clear

echo ''
echo "=============================================="
echo "Next script to run: $Product                  "
echo "=============================================="

sleep 5
