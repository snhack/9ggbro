#!/bin/bash

#9ggbro
#Nginx ServerBlocks Manager
#14/10/2018
#Anthony DOMINGUE & Etienne SELLAN

#config
scriptName="Nginx ServerBlocks Manager"
NginxConfigFilePath="./dev.conf"
useFirewall=false
pathForCertificates="./"
pathForKeys="./"

: ${DIALOG_OK=0}
: ${DIALOG_CANCEL=1}
: ${DIALOG_HELP=2}
: ${DIALOG_EXTRA=3}
: ${DIALOG_ITEM_HELP=4}
: ${DIALOG_ESC=255}

menu(){
    cmd=(dialog --backtitle "$scriptName" --cancel-label "Exit" --menu "Menu" 10 70 16)
    options=("List" "View and modify Vhost"
        "Add" "Add Vhost to configuration"
        "Information" "Informations about this webserver")
    selection=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)
    status=$?
    case ${status} in
        ${DIALOG_OK})
            case ${selection} in
                List)
                    listMenu
                ;;
                Add)
                    serverNameMenu
                ;;
                Information)
                    infos=$(NginxCheckStatus)
                    dialog --backtitle "$scriptName" --title "Webserver informations" --msgbox "$infos" 10 70
                    menu
                ;;
            esac
        ;;
        ${DIALOG_CANCEL})
            clear
        ;;
    esac
}

listMenu(){
    options=()
    
    for index in ${!serversNames[@]};do
        options+=("$index-${serversNames[$index]}")
        if [ ${serversSSL[$index]} == "on" ]
        then
            date=$(getCertificateExpiration ${serversCertificate[$index]})
            options+=("https->$date")
        else
            options+=(" ")
        fi
    done
    
    cmd=(dialog --backtitle "$scriptName" --cancel-label "Back" --menu "List" 15 70 15)
    selection=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)
    status=$?
    case ${status} in
        ${DIALOG_OK})
            actionMenu ${selection}
        ;;
        ${DIALOG_CANCEL})
            menu
        ;;
        ${DIALOG_ESC})
            menu
        ;;
    esac
}

actionMenu(){
    
    serverId=$(echo $1 | cut -d '-' -f1)
    
    options=()
    
    for property in "${dataNames[@]}"
    do
        propertyPlace=$property[$serverId]
        options+=("$property")
        options+=("${!propertyPlace}")
    done
    
    options+=("Delete" "")
    
    cmd=(dialog --backtitle "$scriptName" --cancel-label "Back" --menu "Edition" 15 70 15)
    selection=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)
    status=$?
    case ${status} in
        ${DIALOG_OK})
            if [ ${selection} == "Delete" ]
            then
                deleteFromInventory $serverId
            else
                modificationMenu ${selection} $serverId
            fi
        ;;
        ${DIALOG_CANCEL})
            menu
        ;;
        ${DIALOG_ESC})
            menu
        ;;
    esac
}

modificationMenu(){
    serverId=$2
    propertyName=$1
    propertyPlace=$propertyName[$serverId]
    result=$(dialog --backtitle "$scriptName" --cancel-label "Back" --inputbox "New value for $propertyName" 10 40 "${!propertyPlace}" 2>&1 >/dev/tty)
    status=$?
    case ${status} in
        ${DIALOG_OK})
            editProperty $serverId $propertyName ${result} 
        ;;
        ${DIALOG_CANCEL})
            actionMenu $serverId
        ;;
        ${DIALOG_ESC})
            actionMenu $serverId
        ;;
    esac
}

serverNameMenu(){
    result=$(dialog --backtitle "$scriptName" --cancel-label "Back" --inputbox "New server name" 10 40 "exemple.com" 2>&1 >/dev/tty)
    status=$?
    case ${status} in
        ${DIALOG_OK})
            serverPortMenu ${result}
        ;;
        ${DIALOG_CANCEL})
            menu
        ;;
        ${DIALOG_ESC})
            menu
        ;;
    esac
}

serverPortMenu(){
    serverName=$1
    result=$(dialog --backtitle "$scriptName" --cancel-label "Back" --inputbox "New server port" 10 40 "80" 2>&1 >/dev/tty)
    status=$?
    case ${status} in
        ${DIALOG_OK})
            serverTypeMenu $serverName ${result}
        ;;
        ${DIALOG_CANCEL})
            serverNameMenu
        ;;
        ${DIALOG_ESC})
            menu
        ;;
    esac
}

serverTypeMenu(){
    serverName=$1
    serverPort=$2
    cmd=(dialog --backtitle "$scriptName" --cancel-label "Back" --menu "New server type" 10 70 16)
    options=("local" ""
             "proxy_pass" "")
    selection=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)
    status=$?
    case ${status} in
        ${DIALOG_OK})
            serverDestinationMenu $serverName $serverPort ${selection}
        ;;
        ${DIALOG_CANCEL})
            serverPortMenu $serverName
        ;;
        ${DIALOG_ESC})
            menu
        ;;
    esac
}

serverDestinationMenu(){
    serverName=$1
    serverPort=$2
    serverType=$3
    
    result=$(dialog --backtitle "$scriptName" --cancel-label "Back" --inputbox "New server destination" 10 40 "Destination" 2>&1 >/dev/tty)
    status=$?
    case ${status} in
        ${DIALOG_OK})
            serverSSLMenu $serverName $serverPort $serverType ${result}
        ;;
        ${DIALOG_CANCEL})
            serverTypeMenu $serverName $serverPort
        ;;
        ${DIALOG_ESC})
            menu
        ;;
    esac
}

serverSSLMenu(){
    serverName=$1
    serverPort=$2
    serverType=$3
    serverDestination=$4
    
    cmd=(dialog --backtitle "$scriptName" --cancel-label "Back" --menu "New server SSL configuration" 10 70 16)
    options=("on" ""
             "off" "")
    selection=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)
    status=$?
    case ${status} in
        ${DIALOG_OK})
            if [ ${selection} == "off" || $(openssl --help >/dev/null 2>&1; echo $?) -eq "0" ]
            then
                addVhost $serverName $serverPort $serverType $serverDestination ${selection}
            else
                dialog --backtitle "$scriptName" --title "OpenSSL installation" --msgbox "You must install OpenSSL" 10 70
                menu
            fi
        ;;
        ${DIALOG_CANCEL})
            serverDestinationMenu $serverName $serverPort $serverType
        ;;
        ${DIALOG_ESC})
            menu
        ;;
    esac
}

NginxCheckStatus(){
    if [ $(nginx -v >/dev/null 2>&1; echo $?) -ne "0" ]
    then
        echo "Nginx not installed"
    else
        
        echo "Web server installed : Nginx"
        
        echo "$(nginx -v)"
        
        [ $(systemctl status nginx >/dev/null 2>&1; echo $?) -eq "0" ] && NginxStatus="running" || NginxStatus="stopped"
        echo "Nginx status : $NginxStatus"
        
        [ $(nginx -t >/dev/null 2>&1; echo $?) -eq "0" ] && NginxConfigCheck="success" || NginxConfigCheck="fail"
        echo "Nginx config check : $NginxConfigCheck"
    
    fi
}

loadInventory(){
    echo "Loading inventory..."
    
    dataNames=("serversNames" "serversPorts" "serversSSL" "serversCertificate" "serversKey" "serversLocationType" "serversLocationData")

    loadCounter="0"
    iMax=$(grep -c "server {" $NginxConfigFilePath)
    i=-1
    while IFS= read -r line;do
        echo ${loadCounter} | dialog --title "Loading inventory" --gauge "Please wait" 10 70 0
        [ $(echo $line | grep "server {" >/dev/null 2>&1; echo $?) -eq "0" ] && ((i++)) && serversSSL[$i]="off"
        
        [ $(echo $line | grep "server_name" >/dev/null 2>&1; echo $?) -eq "0" ] && serversNames[$i]=$( echo $line | cut -d ' ' -f2 | tr -d ';' )
        [ $(echo $line | grep "listen" >/dev/null 2>&1; echo $?) -eq "0" ] && serversPorts[$i]=$( echo $line | cut -d ' ' -f2 | tr -d ';' )
        [ $(echo $line | grep "ssl on" >/dev/null 2>&1; echo $?) -eq "0" ] && serversSSL[$i]="on"
        [ $(echo $line | grep "ssl_certificate " >/dev/null 2>&1; echo $?) -eq "0" ] && serversCertificate[$i]=$( echo $line | cut -d ' ' -f2 | tr -d ';' )
        [ $(echo $line | grep "ssl_certificate_key" >/dev/null 2>&1; echo $?) -eq "0" ] && serversKey[$i]=$( echo $line | cut -d ' ' -f2 | tr -d ';' )
        [ $(echo $line | grep "root /" >/dev/null 2>&1; echo $?) -eq "0" ] && serversLocationType[$i]="root" && serversLocationData[$i]=$( echo $line | cut -d ' ' -f2 | tr -d ';' )
        [ $(echo $line | grep "proxy_pass" >/dev/null 2>&1; echo $?) -eq "0" ] && serversLocationType[$i]="proxy_pass" && serversLocationData[$i]=$( echo $line | cut -d ' ' -f2 | tr -d ';' )
        loadCounter=$(echo "scale=2; $i/${iMax}*100" | bc -l)
    done < $NginxConfigFilePath
    
    echo "Inventory complete !"
}

addVhost(){
    newID=$(( ${#serversNames[@]} + 1 ))
    serversNames[$newID]=$1
    serversPorts[$newID]=$2
    serversLocationType[$newID]=$3
    serversLocationData[$newID]=$4
    if [ $5 == "on" ]
    then
        serversSSL[$newID]="on"
        if [ -z "$6" ]
        then
            sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout $pathForKeys$1.key -out $pathForCertificates$1.crt
            serversCertificate[$newID]="$pathForCertificates$1.crt"
            serversKey[$newID]="$pathForKeys$1.key"
        else
            serversCertificate[$newID]=$6
            serversKey[$newID]=$7
        fi
    else
        serversSSL[$newID]="off"
    fi
    
    writeConfigFile
    
    ip=$(hostname --ip-address)
    dialog --backtitle "$scriptName" --title "New server information" --msgbox "$ip:$serverPort" 10 70
    
    menu
}

editProperty(){
    vhostID=$1
    propertyName=$2
    newValue=$3
    
    propertyName=$propertyName[$vhostID]
    
    eval $propertyName=$newValue
    
    writeConfigFile
    
    actionMenu "$vhostID-return"
}

writeConfigFile(){
    path=$NginxConfigFilePath
    echo "" > $path
    for index in ${!serversNames[@]};do
        echo "server {" >> $path
        echo "  listen ${serversPorts[$index]};" >> $path
        echo "  server_name ${serversNames[$index]};" >> $path
        echo "  ssl ${serversSSL[$index]};" >> $path
        if [ ${serversSSL[$index]} == "on" ]
        then
            echo "  ssl_certificate ${serversCertificate[$index]};" >> $path
            echo "  ssl_certificate_key ${serversKey[$index]};" >> $path
        fi
        echo "  location / {" >> $path
        echo "      ${serversLocationType[$index]} ${serversLocationData[$index]};" >> $path
        echo "  }" >> $path
        echo "}" >> $path
    done
    
    systemctl reload nginx
    
    if [ $useFirewall ]
    then
        setFirewallRules
    fi
}

setFirewallRules(){
    for index in ${!serversNames[@]};do
        sudo firewall-cmd --zone=public --add-port=${serversPorts[$index]}/tcp
    done
}

getCertificateExpiration(){
    certificatePath=$1
    expirationDate=$(date -jf "%b %e %H:%M:%S %Y %Z" "$(openssl x509 -enddate -noout -in "$certificatePath"|cut -d= -f 2)" +"%d/%m/%Y")
    echo $expirationDate
}

deleteFromInventory(){
    idToRemove=$1
    for property in "${dataNames[@]}"
    do
        property=$property[$idToRemove]
        eval unset $property
    done
    
    writeConfigFile
    
    listMenu
}


#execution

if [ $( dialog --help >/dev/null 2>&1; echo $?) -eq "0" ]
then
    loadInventory
    menu
else
    echo "Sorry, you must install dialog"
fi
