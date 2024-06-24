#!/bin/bash
#
# The purpose of this script is to create an apache config for a CS/metasploit redirector
#
#


GREEN='\033[0;92m'
RED='\033[0;31m'
YELLOW='\033[0;93m'
NC='\033[0m'
MULTICONT=""


# Trap Functions
function control_c {
    echo -e $NC
    exit $?
}

function error_e {
    echo -e $RED
    echo "Error $1 occurred on $2"
    echo -e $NC
}

# Trap commands for ctrl-c and erro, so we can change the text color...that is all
trap control_c SIGINT
trap control_c SIGTERM
trap 'error_e $? $LINENO' ERR

function startLetsEncrypt() {
    #
    # This is the letsencrypt function
    # It will install letsencrypt if not present and then request certs for your domain 
    #
	
    echo "Running certbot"
    # First check if certbot/letsencrypt is installed
	if [ -n $( command -v certbot ) ]; then
		# if it is not, we need to determine the correct pacakge manager to use - either yum or apt are tested for now
        PKG_MANAGER=$( command -v yum || command -v apt-get )
		if [ ! -z "$PKG_MANAGER" ]; then
			echo "Installing cerbot, cause it ain't on this system"
			echo "Will need sudo rights, if you didn't run this as sudo"
			sudo ${PKG_MANAGER} install certbot
		else
			echo -e "${RED}Certbot isn't installed and I tried to do it for you but I can't identifiy your package manager. Please install it manually and run this script again${NC}"
			exit 1
		fi
	fi

    # Certbot is installed, lets run it
	DOMAIN=$1
	EMAIL="admin@${DOMAIN}"
	certbot certonly --standalone -d $DOMAIN
	if [ ! $? -eq 0 ]; then
        # if certbot failed, we gotta end it like a train wreck
		echo -e "${RED}Certbot failed, it's dark and cold, i'm scared..{$NC}"
		exit 1
	fi

    # Certs are moved to the correct location so docker can get to them, may be useful you add a link instead of cp?
	sudo cp "/etc/letsencrypt/live/${DOMAIN}/cert.pem" certs/server.pem
	sudo cp "/etc/letsencrypt/live/${DOMAIN}/privkey.pem" certs/server-key.pem
	sudo cp "/etc/letsencrypt/live/${DOMAIN}/chain.pem" certs/serverCA.pem
}

function startOpenSSL() {
	#
    # This is the self signed cert function
    # It will create self signed certs for you based on domain or IP you entered in during main script
    #
    DOMAIN=$1
	EMAIL="admin@${DOMAIN}"
	# We are going to pick a random state for the list below...for secret squirrel status
    myState=(AL AK AZ AR CA CO CT DE GA HI ID IL IN IA KS MD MI MN MS OH OK RI SC SD TN TX WV WY WI) 
	size=${#myState[@]}
	state=$(($RANDOM % $size))
	subj="/C=US/ST=${myState[$state]}/O=${DOMAIN}/localityName=${DOMAIN}/commonName=${DOMAIN}/organizationalUnitName=${DOMAIN}/emailAddress=${EMAIL}"
	PASSPHRASE=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
	
    # Generate the server private key
	openssl genrsa -des3 -out certs/server-key.pem -passout pass:$PASSPHRASE 2048

	# Generate the CSR
	openssl req \
		-new \
		-batch \
		-subj "$(echo -n "$subj")" \
		-key certs/server-key.pem \
		-out certs/server.csr \
		-passin pass:$PASSPHRASE

	# Strip the password so we don't have to type it every time we restart Apache
	openssl rsa -in certs/server-key.pem -out certs/server-key.pem -passin pass:$PASSPHRASE

	# Generate the cert (good for 10 years)
	openssl x509 -req -days 3650 -in certs/server.csr -signkey certs/server-key.pem -out certs/server.pem

	cp certs/server.pem certs/serverCA.pem
}

function getCerts() {
    #
	# This function determines how you want to get ssl certs
	# You only have three options - letsencrypt, self signed, provide your own
    # This function is only run if you specifiy https during the main script run
    #
    echo ""
	let d=0
	HOSTADDR=$1
    LETSENC=$2
    echo -e "${GREEN}Looks like you want to run HTTPS${YELLOW}"
	while true; do
		echo "We need to generate certs first, here are the options"
		echo -e $GREEN
	    echo " 1. Use Letsencrypt to generate certs"
        echo " 2. Generate self signed certs for me"
		echo " 3. I've got my own certs, I'll provide the path"
		echo -e $YELLOW
		read -p "What say you: " CERTCHOICE
		case $CERTCHOICE in
			1)  
                # Letsencrypt/certbot wont let you create a cert using only an IP address, so if no domain name was specificed in the main script then we gotta 86 this....for your own good 
                if [ "$LETSENC" -eq 0 ]; then 
                    # Start letsencrypt function
				    startLetsEncrypt $HOSTADDR
				    d=1
                else
                    echo -e "${RED}Since you don't have a domain name to use, we can't use letsencrypt to create certs. Self signed certs will still work for an IP though${YELLOW}"
				fi
                ;;
			2)
                # start openssl function
				startOpenSSL $HOSTADDR
				d=1
				;;
			3)
                # ask user for certs. if they fail to provide valid paths three times in a row we end the world.
				let c=0
				while true; do
					echo ""
					if (($c >= 3)); then
						echo -e $RED
						echo "I am having trouble finding your certificate files, it's over for us. You were great"
						echo "Please check paths and permissions, or use another option"
						echo $YELLOW
						exit 1
					fi
					read -p "Please enter the full path to the server certificate file: " userCertFile
					read -p "Please enter the full path to the server key file: " userKeyFile
					read -p "Please enter the full path to the CA file: " userCaFile
						if [[ ! -f "$userCertFile" ]]; then
							echo -e "${RED}Can't find server certificate file, check path and try again${YELLOW}"
						elif [[ ! -f "$userKeyFile" ]]; then
							echo -e "${RED}Can't find server key file, check path and try again${YELLOW}"
						elif [[ ! -f "$userCaFile" ]]; then
							echo -e "${RED}Can't find CA file, check path and try again${YELLOW}"
						else
							cp $userCertFile "certs/server.pem"
							cp $userKeyFile "certs/server-key.pem"
							cp $userCaFile "certs/serverCA.pem"
							echo -e "${GREEN}Found all files, moving on...${YELLOW}"
							break;
						fi
						((++c))
				done
				d=1	
				;;
		esac
		if (($d == 1)); then
			break;
		fi
	done
}

function getMultiCondition() {
    #
    # This function gets the or/and condition needed for multiple rewrite conditions
    #
    
    echo "Ok, we need to know how each condition should be met - should it be [OR] or [AND]"
    echo " - [OR] requires that only one of the conditions match to return true"
    echo " - [AND] requires that all conditions match to return true"
    echo "We will only use [OR] or [AND] for all conditions, there is no mix or matching here"
    while true; do
        echo "Tell me what you want, tell me what you really really want:"
        echo -e $GREEN
        echo " 1. [OR]"
        echo " 2. [AND]" 
        echo -e $YELLOW
        read -p "PiCK a NuMbER: " THECHOICE
        case $THECHOICE in
            1)
                MULTICONT="OR"
                break;
                ;;
            2)
                MULTICONT="AND"
                break;
                ;;
            *)
                echo "NOT AN OPTION, STOP IT"
                ;;
        esac
    done

}

function redirectRule() {
    #
    # This function creates the redirect rule for any rewrite condition
    #    
    echo ""
    # We try to be smart here and let you select your teamserver or a new location to redirect the previous condition rule, when a match happens
    echo "What location do you want these conditions to redriect to?"
    echo -e ${GREEN}
    echo "  1. Your Teamserver - ${CSTEAMSERVER}"
    echo "  2. A random location"
    echo -e ${YELLOW}
    read -p "What say you, sire: " REDCH
    case $REDCH in
        1)
            # Add redirect rule with teamserver protocol, ip, and port. It's party time!
            echo "  # Redirect traffic to ${CSPROTO}://${CSTEAMSERVER}:${CSPORT}" >> conf/apache_redirect.conf
            echo "  RewriteRule ^.*$ ${CSPROTO}://${CSTEAMSERVER}:${CSPORT}%{REQUEST_URI} [L,P,NE]" >> conf/apache_redirect.conf            
            ;;
        2)
            # Add redirect rule with for custom location
            echo "Please enter the location you want to redirect to, in the following format 'protocol://domain_or_ip:port'. <-- NO TRAIL FORWARD SLASH"
            read REDLOCAL
            echo "  # Redirect traffic to ${REDLOCAL}" >> conf/apache_redirect.conf
            echo "  RewriteRule ^.*$ ${REDLOCAL}%{REQUEST_URI} [L,P,NE]" >> conf/apache_redirect.conf
            ;;
    esac
    # Add a space to the config file to seperate condition and rewrite rule chunks, for easy reading only
    echo "" >> conf/apache_redirect.conf
}

function PROXYALL () {
    #
    # This function creates the proxy pass rule to redirect all traffic 
    #  if we want to have this redirector just redirect all traffic, it's better to use a rev proxy
    #   instead of a rewrite rule. So "they" say 
    echo "What location do you want to redirect all traffic to?"
    echo -e ${GREEN}
    echo "  1. Your Teamserver - ${CSPROTO}://${CSTEAMSERVER}:${CSPORT}"
    echo "  2. A different location"
    echo -e ${YELLOW}
    read -p "What say you, sire: " REDCH
    case $REDCH in
        1)
            # Add proxy rule with teamserver protocol, ip, and port. It's party time!
            echo "  # Proxy traffic to ${CSPROTO}://${CSTEAMSERVER}:${CSPORT}" >> conf/apache_redirect.conf        
            echo "  ProxyPass / ${CSPROTO}://${CSTEAMSERVER}:${CSPORT}/" >> conf/apache_redirect.conf
            echo "  ProxyPassReverse / ${CSPROTO}://${CSTEAMSERVER}:${CSPORT}/" >> conf/apache_redirect.conf
            ;;
        2)
            # Add redirect rule with for custom location
            echo "Please enter the location you want to redirect to, in the following format 'protocol://domain_or_ip:port'."
            read -p REDLOCAL
            echo "  # Proxy traffic to ${REDLOCAL}" >> conf/apache_redirect.conf        
            echo "  ProxyPass / ${REDLOCAL}/" >> conf/apache_redirect.conf
            echo "  ProxyPassReverse / ${REDLOCAL}/" >> conf/apache_redirect.conf
            ;;
    esac
}

function getRandUri() {
    #
    # This is the random uri keyword function
    # We get the amount of characters they want to add and create the regex for it before sending it back to the condition rule
    #
    echo -e ${GREEN}
    echo "You entered a random char keyword as a part of a path - ${1}"
    echo -e ${YELLOW}
    read -p "How many random charaters do you want this path to match: " RANDCHARCOUNT
    # loop over the length of the randcharcount and add a .
    for (( r = 1; r <= $RANDCHARCOUNT; r++ )); do
        RANPATH+="."
    done
    # We need to append/prepend the uri with forward slashes, because standards or whatever
    #if [ ${1:0:1} != "/" ]; then
    #    RANPATH="/${1}"
    #fi
    #if [ ${1: -1} != "/" ]; then
    #    RANPATH="${1}/"
    #fi
    #echo $RANPATH

    # Insert the newely created random path regex into the overall uri
    RANDURI=$(sed -e "s/random_char_path/${RANPATH//\//\\/}/g" <<< $1)
    #echo $RANDURI
}

function URI(){
    #
    # This is the function to create a conditional rule for a URI path
    #
    
    # This is the "readme for this section"
    #if (( $1 == 0 )); then 
    echo -e $GREEN
    echo "  For the URI/URL redirect condition, you need to specify at least one path, such as /updates/"
    echo "  Remeber these paths are specific to whatever C2 profile you have employed"
    echo ""
    echo "  Here are some examples of valid paths to enter here: "
    echo "      1. /updates/ms_windows/"
    echo "      2. /include/images/image1.jpg"
    echo "      3. /admin/"
    echo ""
    echo "  You can specify multiple paths seperated by a comma: /testadmin/,/hellothere/,/download/images.zip"
    echo ""
    echo "  Here are some keywords to use as well"
    echo -e "      1. ${YELLOW}random_char_path${GREEN} - This tells the script you want to create a condition rule for"
    echo "           a randon character URI, with a set length determined later. i.e. A target host making a GET request to"
    echo "           a random four character URI configured in the Malleable C2 profile"
    echo ""
    echo "  Finally, please note that for each URI condition you create, there must be a redirect rule that follows."
    echo -e $YELLOW
    #fi
    echo -e "Please specify the paths you want to use in this one condition rule, multiple paths can be sperated by a comma (no spaces): "
    read CONPATHS
    
    # If the url path entered contains a comma, we assume the user wanted to enter two paths. So split it and loop, ok
    if [[ $CONPATHS == *","* ]]; then
        let a=0
        let f=0
        IFS=',' read -ra APATH <<< "$CONPATHS"
        for i in "${APATH[@]}"; do
            # Because we are assuming multiple paths were entered, we need to seperate each uri with the or clause - "|"
            # To do this, we catch the first instance of the loop and exclude the or clause from being added to the uri
            # All subsequent loops with then prepend the or clause to the uri
            if (( $a == 0 )); then
                # If more keywords are needed, a case statement will be better
                # Catch random keyword
                if [[ $i == *"random_char_path"* ]]; then
                    getRandUri $i
                    i=$RANDURI
                fi
                # We need to append/prepend the uri with forward slashes, because standards or whatever
                if [ ${i:0:1} != "/" ]; then
                    i="/${i}"
                fi
                #if this is a file, don't add /
                SUB='.'
                if [[ "$i" == *"$SUB"* ]]; then
                    f=1
                elif [ ${i: -1} != "/" ]; then
                    i="${i}/"
                fi
                if (( $f == 0 )); then 
                    echo -e $YELLOW
                    echo -e "Do you want the path, ${i} , to match exactly or match this path and any subpaths under it? "
                    echo -e " 1. Exact Match"
                    echo -e " 2. Sub Path Match"
                    read PATHMATCH
                    case $PATHMATCH in
                        1)
                            ;;
                        2)
                            i="${i}(.*)"
                            ;;
                        *)
                            echo "Not an option, we will decide for you - exact match it is"
                            echo " It wasn't that hard...."
                            ;;
                    esac
                fi
                CONURL="${i}"
                a=1
                f=0
            else
                # Catch random keyword
                if [[ $i == *"random_char_path"* ]]; then
                    getRandUri $i
                    i=$RANDURI
                fi
                # We need to append/prepend the uri with forward slashes, because standards or whatever
                if [ ${i:0:1} != "/" ]; then
                    i="/${i}"
                fi
                #if this is a file, don't add /
                SUB='.'
                if [[ "$i" == *"$SUB"* ]]; then
                    f=1
                elif [ ${i: -1} != "/" ]; then
                    i="${i}/"
                fi
                if (( $f == 0 )); then 
                    echo -e $YELLOW
                    echo -e "Do you want the path, ${i} , to match exactly or match this path and any subpaths under it? "
                    echo -e " 1. Exact Match"
                    echo -e " 2. Sub Path Match"
                    read PATHMATCH
                    case $PATHMATCH in
                        1)
                            ;;
                        2)
                            i="${i}(.*)"
                            ;;
                        *)
                            echo "Not an option, we will decide for you - exact match it is"
                            echo " It wasn't that hard...."
                            ;;
                    esac
                fi
                CONURL+="|${i}"
                f=0
            fi
        done

        # Add uri to config
        echo "  # Conditional rule for urls: ${CONPATHS}" >> conf/apache_redirect.conf
        echo "  RewriteCond %{REQUEST_URI} ^(${CONURL})?$ [NC]">> conf/apache_redirect.conf
    
    # No commas were present, so treat it as one uri
    else
        let f=0
        # Catch random keyword
        if [[ $CONPATHS == *"random_char_path"* ]]; then
            getRandUri $CONPATHS
            CONPATHS=$RANDURI
        fi
        # We need to append/prepend the uri with forward slashes, because standards or whatever
        if [ ${CONPATHS:0:1} != "/" ]; then
            CONPATHS="/${CONPATHS}"
        fi
        # We need to append/prepend the uri with forward slashes, because standards or whatever

        SUB='.'
        if [[ "$CONPATHS" == *"$SUB"* ]]; then
            f=1
        elif [ ${CONPATHS: -1} != "/" ]; then
            CONPATHS="${CONPATHS}/"
        fi
        if (( $f == 0 )); then 
            echo -e $YELLOW
            echo -e "Do you want the path, ${i} , to match exactly or match this path and any subpaths under it? "
            echo -e " 1. Exact Match"
            echo -e " 2. Sub Path Match"
            read PATHMATCH
            case $PATHMATCH in
                1)
                    ;;
                2)
                    CONPATHS="${CONPATHS}(.*)"
                    ;;
                *)
                    echo "Not an option, we will decide for you - exact match it is"
                    echo " It wasn't that hard...."
                    ;;
            esac
                fi

        echo "  # Conditional rule for url: ${CONPATHS}" >> conf/apache_redirect.conf
        echo "  RewriteCond %{REQUEST_URI} ^${CONPATHS}?$ [NC]" >> conf/apache_redirect.conf
    fi
    
    # If only the URI option was selected in the main script, run the redirect rule function
    # This is skipped if the user wanted to add both a URI and UserAgent for one redirect rule
    if (( $2 == 1 )); then
        redirectRule 0
    fi
}

function USERAGENT() {
    #
    # This is the function to create a conditional rule for a user agent
    #
    
    # This is the "readme for this section"
    #if (( $1 == 0 )); then
    echo -e $GREEN
    echo "  For the User Agent redirect condition, you need to specify at least one User Agent string"
    echo "  Remeber these User Agents are specific to whatever C2 profile you have employed"
    echo ""
    echo "  Here are some examples of valid User Agents: "
    echo "      1. Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.36"
    echo "      2. Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:53.0) Gecko/20100101 Firefox/53.0"
    echo "      3. Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/51.0.2704.79 Safari/537.36 Edge/14.14393"
    echo ""
    echo "  Here are some keywords to use as well"
    echo -e "      1. ${YELLOW}blank_user_agent${GREEN} - This tells the script you want to create a condition rule for"
    echo "           when a request is made with no user agent. i.e. A target host making a GET request and supplies a"
    echo "           a blank UserAgent string, as configured in the Malleable C2 profile"
    echo ""
    echo "  Finally, please note that for these User Agent conditions you create now, there must be a redirect rule that follows."
    echo -e $YELLOW
    #fi
    echo -e "Please specify the User Agent you want to use in this one condition rule: "
    read CONUSERA


    # To make life a little easier, we will loop over this question so a user can add as many useragent strings for this one redirect rule
    while true; do
        echo ""
        read -p "Do you wan't to add another User Agent string for this one redirect rule? (y/N)" yn
        case $yn in
            [Yy]* )
                # We don't need to ask for the OR/AND condition for this one. Mulitple useragent headers assumes an OR condition.

                # Catch blank user agent keyword
                if [[ $CONUSERA == *"blank_user_agent"* ]]; then
                    echo "  # Blank user agent conditional rule" >> conf/apache_redirect.conf
                    echo "  RewriteCond %{HTTP_USER_AGENT} ^$ [NC,OR]" >> conf/apache_redirect.conf
                else
                    # No blank keyword, so business as usual
                    echo "  # Conditional rule for UserAgent: ${CONUSERA}" >> conf/apache_redirect.conf
                    
                    # Before we add the user agent to the config file all spaces, periods, and parentheses need to be escaped 
                    CONUSERA=$(sed -e 's/\./\\&/g;s/\ /\\&/g;s/)/\\&/g;s/(/\\&/g' <<< $CONUSERA)
                    echo "  RewriteCond %{HTTP_USER_AGENT} ^${CONUSERA}?$ [NC,OR]" >> conf/apache_redirect.conf
                fi
                
                echo -e $YELLOW
                echo -e "Please specify the User Agent you want to use in this one condition rule: "
                read CONUSERA
                ;;
            [Nn]* )

                # Catch blank user agent keyword
                if [[ $CONUSERA == *"blank_user_agent"* ]]; then
                    echo "  # Blank user agent conditional rule" >> conf/apache_redirect.conf
                    echo "  RewriteCond %{HTTP_USER_AGENT} ^$ [NC]" >> conf/apache_redirect.conf
                else
                    # No blank keyword, so business as usual
                    echo "  # Conditional rule for UserAgent: ${CONUSERA}" >> conf/apache_redirect.conf
                    
                    # Before we add the user agent to the config file all spaces, periods, and parentheses need to be escaped 
                    CONUSERA=$(sed -e 's/\./\\&/g;s/\ /\\&/g;s/)/\\&/g;s/(/\\&/g' <<< $CONUSERA)
                    echo "  RewriteCond %{HTTP_USER_AGENT} ^${CONUSERA}?$ [NC]" >> conf/apache_redirect.conf
                fi

                echo -e "${GREEN}OK fine${YELLOW}"
                break
                ;;
        esac
    done
    # If only the User Agent option was selected in the main script, run the redirect rule function
    # This is skipped if the user wanted to add both a URI and UserAgent for one redirect rule
    if (( $2 == 1 )); then
        redirectRule 0
    fi
}

function COOKIE() {
    #
    # This is the function to create a conditional rule for a cookie header
    #
    
    # This is the "readme for this section"
    #if (( $1 == 0 )); then
    echo -e $GREEN
    echo "  For a Cookie redirect rule, all we need is the cookie name."
    echo "  Example: _mysession"
    echo ""
    echo "  The cookie value match is a wildcard, so anything can be present in a cookie for the rule to trigger."
    echo "  In the future we will look at specifying the value type to match - think base64 encoded, all numbers, or values of a specific length"
    echo ""
    echo "  Finally, please note that for these Cookie conditions you create now, there must be a redirect rule that follows."
    echo -e $YELLOW
    #fi
    echo -e "Please specify the cookie name you want to use in this one condition rule: "
    read COOKNAME
    
    while true; do
        echo ""
        read -p "Do you wan't to add another cookie header for this one redirect rule? (y/N)" yn
        case $yn in
            [Yy]* )
                if [ -z "$MULTICONT" ]; then 
                    getMultiCondition
                fi

                # Add Last COOKIE to config
                echo "  # [${MULTICONT}] Conditional rule for cookie: ${COOKNAME}" >> conf/apache_redirect.conf
                if [ "${MULTICONT}" == "AND" ]; then
                    echo "  RewriteCond %{HTTP_COOKIE} ${COOKNAME}=([^;]+) [NC]">> conf/apache_redirect.conf
                else
                    echo "  RewriteCond %{HTTP_COOKIE} ${COOKNAME}=([^;]+) [NC,${MULTICONT}]">> conf/apache_redirect.conf
                fi
                
                echo -e $YELLOW
                echo -e "Please specify the cookie name you want to use in this one condition rule: "
                read COOKNAME
                
                ;;
            [Nn]* )
                # Add Last COOKIE to config
                echo "  # Conditional rule for cookie: ${COOKNAME}" >> conf/apache_redirect.conf
                echo "  RewriteCond %{HTTP_COOKIE} ${COOKNAME}=([^;]+) [NC]">> conf/apache_redirect.conf

                echo -e "${GREEN}OK, fine. Jerk${YELLOW}"
                break
                ;;
        esac
    done
    if (( $2 == 1 )); then
        redirectRule 0
    fi
}

#function BOTHCOND() {
    #
    # This function is for adding both a URI path and User Agent string conditions for one redirect rule
    # Calls each funcion and passes a zero to disable the redirectRule call within each function 
    #
#    URI $1 0
#    USERAGENT $1 0
#    redirectRule 0
#}

function ADDCUST() {
    #
    # This is the function to create a conditional rule for some custom entry
    #
    
    # This is the "readme" for this section
    echo -e "${GREEN}"
    echo "  This section allows you to add custom conditional rules directly into the Apache config file."
    echo "  - Make sure your syntax is correct, as this could cause the config to break....and the WORLD"
    echo "  - All periods, spaces, and parentheses need to escaped"
    echo "  - Finally, please note that for these custom condition you create, there must be a redirect rule that follows."
    echo -e "${YELLOW}"
    echo "Please specifiy the custom conditional rule you want to add to the config: "
    read CUSTCON
    # Take ctstom entry and add it to config file. Using this function assumes the user knows what they are doing....that may be a mistake?
    echo "  # Conditional rule for custom string: ${CUSTCON}" >> conf/apache_redirect.conf
    echo "  ${$CUSTON}" >> conf/apache_redirect.conf

    # To make life a little easier, we will loop over this question so a user can add as many custom entries as they want for this one redirect rule
    while true; do
        echo ""
        read -p "Do you wan't to add another custom condition for this one redirect rule? (y/N)" yn
        case $yn in
            [Yy]* )
                echo "Please specifiy another custom conditional rule you want to add to the config: "
                read CUSTCON
                echo "  # Conditional rule for custom string: ${CUSTCON}" >> conf/apache_redirect.conf
                echo "  ${$CUSTON}" >> conf/apache_redirect.conf
                ;;
            [Nn]* )
                echo -e "${GREEN}OK fine${YELLOW}"
                break
                ;;
        esac
    done
    redirectRule 0
}

###############
#
# Main Script
#
###############

echo -e $GREEN 
echo "##########################################"
echo "#"
echo "#  Apahce CS Redirector Config Builder"
echo "#"
echo "##########################################"

# If there is already an apache config, let's confirm they want it overwritten before continuing
if [[ -f conf/apache_redirect.conf ]]; then
    echo -e $RED
    echo "An apache redirect config already exists at conf/apache_redirect.conf"
    echo -e "Running this script will overwrite all enteries in that config file${YELLOW}"
    read -p "Are you sure you want to continue(y/N): " yn
    case $yn in
        [Yy]* )
            echo -e $GREEN
            ;;
        [Nn]* )
            echo "ok, exiting script"
            echo -e $NC
            exit
            ;;
        *)
            echo "ok, exiting script"
            echo -e $NC
            exit
            ;;
    esac
fi

# Get all the relevant info about redirector and teamserver setup - ip/domin, port, protocol for both
echo "Let's get started..."
echo -e $YELLOW

#
# Redirector info
#
read -p "What port do you want this redirector to run on: " REDPORTNUMBER
echo "What protocol will this redirector be using"
echo -e $GREEN
echo " 1. HTTP"
echo " 2. HTTPS"
echo -e $YELLOW
read -p "Please choose: " REDPROTOCOL
# Ask if they have a domain name, if not we will just grab the public ip and use that
read -p "Do you have a domain name you want to use for this redirector (y/N): " yn
case $yn in
    [Yy]* )
        read -p "What's the FQDN you want to use: " REDIRECTOR_ADDR
        NODOMAIN=0
        ;;
    [Nn]* )
        REDIRECTOR_ADDR=$(curl -s ifconfig.io/ip)
        NODOMAIN=1
        ;;
    * )
        REDIRECTOR_ADDR=$(curl -s ifconfig.io/ip)
        NODOMAIN=1
        ;;
esac

#
# Teamserver info
#
read -p "What is the IP or domain name of the CS Team Server: " CSTEAMSERVER
read -p "What port is the CS Team Server using for the beacon: " CSPORT
echo "What protocol is the CS Team Server expecting"
echo -e $GREEN
echo " 1. HTTP"
echo " 2. HTTPS"
echo -e $YELLOW
read -p "Please choose: " CSPROTO
case $CSPROTO in
    1)
        CSPROTO="http"
        ;;
    2)
        CSPROTO="https"
        ;;
    *)
        echo -e "${RED}NO, WRONG${NC}"
        exit
        ;;
esac

mkdir -p conf certs
# Start build of apache virtualhost file
echo "<VirtualHost _default_:${REDPORTNUMBER}>" > conf/apache_redirect.conf
echo "  ServerName  ${REDIRECTOR_ADDR}" >> conf/apache_redirect.conf

# Determine if we need to create certs
if [ "$REDPROTOCOL" == "2" ]; then
    getCerts $REDIRECTOR_ADDR $NODOMAIN
    echo "  SSLEngine On" >> conf/apache_redirect.conf
    echo "  SSLCertificateFile /certs/server.pem" >> conf/apache_redirect.conf
    echo "  SSLCertificateKeyFile /certs/server-key.pem" >> conf/apache_redirect.conf
fi

# Add SSL Proxy bits if teamserver is using SSL
if [ "$CSPROTO" == "https" ]; then
    echo ""
    echo "  # SSL Proxy bits, we may need a better approach than just saying don't verify upstream server certs" >> conf/apache_redirect.conf
    echo "  SSLProxyEngine On" >> conf/apache_redirect.conf
    echo "  ProxyPreserveHost On" >> conf/apache_redirect.conf
    echo "  SSLProxyVerify none" >> conf/apache_redirect.conf
    echo "  SSLProxyCheckPeerCN off" >> conf/apache_redirect.conf
    echo "  SSLProxyCheckPeerName off" >> conf/apache_redirect.conf
fi

# Enable Rewrite Engine
echo "" >> conf/apache_redirect.conf
echo "  RewriteEngine On" >> conf/apache_redirect.conf

# Get redirect rule info
# Hold onto your pants folks, this gonna get cray cray lit
echo -e "${GREEN}We need to determine what condition and redirect rules you want to use. Let's begin shall we?${YELLOW}"

FIRSTTIME=0
NOCATCHALL=0
# We are going to loop over this menu until the user decides they are done adding conditional/redirect rules
while true; do
    echo "Please pick a redirect condition from the list below: "
    echo -e ${GREEN}
    echo "  1. URI/URL Redirect Conditions"
    echo "  2. USER-AGENT Redirect Conditions"
    echo "  3. COOKIE Redirect Conditions"
    echo "  4. Enter Custom Redirect Condition(s)"
    echo "  5. Redirect All Traffic"
    echo "  6. I'm done"
    echo -e ${YELLOW}
    read -p "Please choose an option: " CONDOPT
    case $CONDOPT in
        1)
            URI $FIRSTTIME 1
            ;;
        2)
            USERAGENT $FIRSTTIME 1
            ;;
        3)
            COOKIE $FIRSTTIME 1
            ;;
        4)
            ADDCUST
            ;;
        5)
            PROXYALL
            NOCATCHALL=1
            break
            ;;
        6)
            break
            ;;
    esac
    FIRSTTIME=1    
done

# Add final/catch all redirect rule to config
if (( $NOCATCHALL == 0 )); then
    echo ""
    echo "Finally, if a request doesn't satisfy any of these conditional rules, where do you want the request to be redirected? "
    echo " This is like a catch all, enter the full url - https://google.com, https://example.com, etc."
    read FINALLREDIR
    echo "  # Finall Redirect Rule/Catch all. Redirect to: ${FINALLREDIR}" >> conf/apache_redirect.conf
    echo "  RewriteRule ^.*$ ${FINALLREDIR}? [L,R=302]" >> conf/apache_redirect.conf
fi

# Close the config file
echo "</VirtualHost>" >> conf/apache_redirect.conf
echo -e $GREEN

# Echo config to user
echo "***************************************************"
echo ""
echo "Here is the config file we just created: "
echo -e "${YELLOW}\n"
cat conf/apache_redirect.conf
echo ""
echo -e "${GREEN}***************************************************"

echo ""
echo "***************************************************"
echo ""
echo -e "${YELLOW}Apache config located at: $(pwd)/conf/apache_redirect.conf"
echo -e "${YEELOW}Certs are located at: $(pwd)/certs/"
echo ""
echo -e "${GREEN}***************************************************"
echo ""

# Echo docker run commands
echo ""
echo "***************************************************"
echo ""
echo "To build and run the docker (If you want to), please run the following commands: "
echo ""
echo -e "  ---- To Build ----${YELLOW}"
echo "  docker image build --tag apache-redirect ."
echo -e ${GREEN}
echo -e "  ---- To Run ----${YELLOW}"
echo "  docker container run -p ${REDPORTNUMBER}:${REDPORTNUMBER} --name=apache-redirect --mount type=bind,source="$(pwd)"/certs,target=/certs --mount type=bind,source="$(pwd)"/conf,target=/conf --restart unless-stopped apache-redirect"
echo -e ${GREEN}
echo -e "  ---- To Reload Apache after Cert/Config Change ----${YELLOW}"
echo "  docker exec apache-redirect service apache2 reload"
echo ""
echo -e "${GREEN}***************************************************"
echo ""
echo -e $NC


#END OF SCRIPT. SEE NOTHING FOLLOWS!
