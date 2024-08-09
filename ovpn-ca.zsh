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
	'client_csr'       "${server}/${client}/${client}-csr.pem"
	'client_key'       "${server}/${client}/${client}-key.pem"
	'client_cert'      "${server}/${client}/${client}-cert.pem"
	'client_config'    "${server}/${client}/${client}@${server}.ovpn"
)

function Subj
{
	local cn=$1
	print ${(e)subj}
}

# returns true number of days in $1 years
function Days
{
	local years=$1
	strftime -s now %s
	strftime -s years -r '%F %T' "$(( $(strftime %Y)+$years ))-$(strftime '%m-%d %T')"
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
	[[ -r ${file[config_template]} ]] || {
		print "no template file ${file[config_template]}"
		return 4
	}

	local -a secrets
	secrets=(
		'ca'   'ca_cert'
		'cert' 'client_cert'
		'key'  'client_key' )
	[[ -z $withoutTLSCrypt ]] && secrets+=('tls-crypt' 'tls_crypt')

	integer config
	exec {config} > ${file[client_config]}
	>& $config < ${file[config_template]}
	for k f in $secrets; do
		>& $config <<< '' <<< "<$k>" < <(grep -v '^#' ${file[$f]}) <<< "</$k>"
	done
	exec {config} >&-
}

function ShowClientSerial
{
	[[ -z $server || -z $client  ]] && {
		[[ -z $server ]] && print '$server is not specified'
		[[ -z $client ]] && print '$client is not specified'
		exit 1
	}

	print "ibase=16; ${$($openssl x509 -serial -noout -in ${file[client_cert]})##*=}" | bc
}

function ShowCertExpiration
{
	local cert=$1
	strftime -s now %s
	strftime -s exp -r '%F %TZ' "${$(openssl x509 -dateopt iso_8601 -enddate -noout -in $cert)##*=}"
	(( days = (exp-now)/(24*60*60) ))
	strftime -s date '%F' $exp
	if (( days > 0 )); then
		(( days < 365 )) && print -nP "%F{143}"
		(( days < 200 )) && print -nP "%F{203}"
		print -n "expires $date (in ${(l:4:)days} days)"
	else
		print -nP "%F{95}"
		print -n "expired $date (${(l:3:)$((-days))} days ago)"
	fi
	print -nP "%f"
}

function ShowAllCertsExpiration
{
	[[ -z $server ]] && print '$server is not specified' && exit 1

	local c
	for c in $server/*/*-cert.pem; do
		ShowCertExpiration $c
		print "  ${${c#*/}%/*}"
	done
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
#		print ${(F)${(koi)functions}}
		print -l ${(koi)functions}
		;;
	*)
		$action
		;;
esac
