#!/bin/zsh -e

umask 'u=rwx,g=,o='
zmodload zsh/datetime

[[ -r config ]] && source config
[[ -r ${server}/config ]] && source ${server}/config

action=$1

server=${server:-$s}
client=${client:-$c}

y=1
key=${key:-'ed448'}
subj=${subj:-'/CN=${cn}'}
[[ $key =~ '^rsa' ]] && digest=${digest:-'-sha512'}
pwgen=(pwgen -s -c -n -y 20 1)
caYears=10
serverYears=10
openssl='/usr/bin/openssl'
openvpn='/usr/sbin/openvpn'
export caPassword

typeset -A file
file=(
	'ca_key'           "${server}/ca/${server}_vpn_ca-key.pem"
	'ca_cert'          "${server}/ca/${server}_vpn_ca-cert.pem"
	'dh'               "${server}/${server}/dh.pem"
	'server_csr'       "${server}/${server}/${server}-csr.pem"
	'server_key'       "${server}/${server}/${server}-key.pem"
	'server_cert'      "${server}/${server}/${server}-cert.pem"
	'tls_crypt'        "${server}/${server}/${server}-tlscrypt-key.pem"
	'config_template'  "${server}/${type:+${type}_}client_template.ovpn"
#	'config_template'  "${server}/${(j:_:)${=${:-$type client_template.ovpn}}}"
	'client_csr'       "${server}/${client}/${client}-csr.pem"
	'client_key'       "${server}/${client}/${client}-key.pem"
	'client_cert'      "${server}/${client}/${client}-cert.pem"
	'client_config'    "${server}/${client}/${client}@${server}.ovpn"
)

function Subj
{
	cn=$1
	print ${(e)subj}
}

# returns true number of days in years
function Days
{
	years=$1
	strftime -s now %s
	strftime -s years -r '%Y-%m-%d %T' "$(( $(strftime %Y)+$years))-$(strftime '%m-%d %T')"
	print $(( (years-now)/(24*60*60) ))
}

function MakeDHParams
{
	print "Generating DH params."
	$openssl dhparam -out ${file[dh]} ${key#rsa:}
}

function MakeTLSCrypt
{
	print "Generating TLS crypt key."
	$openvpn --genkey tls-crypt ${file[tls_crypt]}
}

function MakeCAPassword
{
	print "Generated passphrase for CA private key:"
	caPassword=$($pwgen)
	print "Save it in the safe place!"
	print $caPassword
}

function MakeCA
{
	print "Creating CA for $caYears years."
	$openssl req\
		-utf8\
		-new\
		-x509\
		-passout 'env:caPassword'\
		$digest\
		-newkey $key\
		-days $(Days $caYears)\
		-subj "$(Subj "$server vpn ca")"\
		-out ${file[ca_cert]}\
		-keyout ${file[ca_key]}
}

function MakeServerCertificate
{
	print "Creating server for $serverYears years."
	$openssl req\
		-utf8\
		-new\
		-newkey $key\
		-nodes\
		-subj "$(Subj "$server vpn server")"\
		-out ${file[server_csr]}\
		-keyout ${file[server_key]}\
		-addext 'basicConstraints = CA:FALSE'\
		-addext 'keyUsage = digitalSignature, keyEncipherment'\
		-addext 'extendedKeyUsage = serverAuth'
	
	$openssl x509\
		-req\
		-passin 'env:caPassword'\
		-in ${file[server_csr]}\
		-CA ${file[ca_cert]}\
		-CAkey ${file[ca_key]}\
		-CAcreateserial\
		-out ${file[server_cert]}\
		-days $(Days $serverYears)\
		$digest\
		-copy_extensions copy
}


function MakeClientCertificate
{
	print "Creating ${client}@${server} for $y years."
	$openssl req\
		-utf8\
		-new\
		-newkey $key\
		-nodes\
		-subj "$(Subj $client)"\
		-out ${file[client_csr]}\
		-keyout ${file[client_key]}\
		-addext 'basicConstraints = CA:FALSE'\
		-addext 'keyUsage = digitalSignature'\
		-addext 'extendedKeyUsage = clientAuth'
	
 	$openssl x509\
		-req\
		-in ${file[client_csr]}\
		-CA ${file[ca_cert]}\
		-CAkey ${file[ca_key]}\
		-out ${file[client_cert]}\
		-days $(Days $y)\
		-sha512\
		-copy_extensions copy
}

function MakeClientConfig
{
	config="${file[client_config]}"

	[[ -r ${file[config_template]} ]] || {
		print "no template file ${file[config_template]}"
		return 4
	}

	cat ${file[config_template]}  > $config
	print                        >> $config
	print '<ca>'                 >> $config
	cat ${file[ca_cert]}         >> $config
	print '</ca>'                >> $config
	print                        >> $config
	print '<cert>'               >> $config
	cat ${file[client_cert]}     >> $config
	print '</cert>'              >> $config
	print                        >> $config
	print '<key>'                >> $config
	cat ${file[client_key]}      >> $config
	print '</key>'               >> $config
	print                        >> $config
	[[ -z $withoutTLSCrypt ]] && {
		print '<tls-crypt>'          >> $config
		cat ${file[tls_crypt]} | grep -v '^#' >> $config
		print '</tls-crypt>'         >> $config
	}
}

function AddVPN
{
	[[ -z $server ]] && print '$server is not specified' && exit 1
	[[ -d ${server} ]] && print 'VPN aleready exists.' && exit 2
	
	mkdir ${server} ${server}/ca ${server}/${server}
	[[ $key =~ '^rsa' ]] && MakeDHParams
	[[ -z $withoutTLSCrypt ]] && MakeTLSCrypt
	MakeCAPassword
	MakeCA
	chmod a-w ${server}/ca/*pem
	MakeServerCertificate
	chmod a-w ${server}/${server}/*pem
	tree ${server}
	print "Put ovpn template into vpn directory!"
}

function AddClient
{
	[[ -z $server || -z $client  ]] && {
		[[ -z $server ]] && print '$server is not specified'
		[[ -z $client ]] && print '$client is not specified'
		exit 1
	}
	[[ -d ${server}/${client} ]] && 'Client aleready exists.' && exit 3

	mkdir ${server}/${client}
	MakeClientCertificate
	chmod a-w ${server}/${client}/*pem
	MakeClientConfig || true
	tree ${server}/${client}
}

case $action in
	'' | 'help' | '-h' | '--help')
		print "Usage:"
		print "s|server=<server> [c|client=<client> type={template_prefix} y=<years>] $0 {AddClient|AddVPN}"
		print
		print "All functions:"
		print ${(F)${(k)functions}}
		;;
	*)
		$action
		;;
esac
