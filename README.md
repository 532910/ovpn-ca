# ovpn-ca.zsh


## A simple tool for OpenVPN CA

Generates CA, server secrets and ovpn client configs for OpenVPN in TLS mode.
A pretty simple tool.


## HOWTO

```
s=<vpn_name> ovpn-ca.zsh AddVPN
```

A folder `vpn_name` will be created with CA and server files.
CA private key will be encrypted with a password printed on stdout. Save it in the safe place!
Copy `sample_client_template.ovpn` into `vpn_name/client_template.ovpn` and edit it.
It's just a head that will be appended with secrets to make a client's `.ovpn` file.

```
s=<vpn_name> c=<client_name> ovpn-ca.zsh AddClient
```

Put `_vpn_ca-cert.pem` and `-(cert|key|tlscrypt-key).pem` onto the server
and give `client@vpn_name.ovpn` to the client.


## Required Debian packages

`zsh openssl openvpn pwgen tree`
`pwgen` can be replaced with a similar tool, but others are hardcoded


## Some options

```
s|server=<server>
c|client=<client>
```

Default values                   | Description
-------------------------------- | ---------------------------------
`y=1`                            | client certificate years validity
`caYears=10`                     | CA certificate years validity
`serverYears=10`                 | server certificate years validity
`key=ed448`                      | other possible values: `ed25519`, `rsa:4096`
`digest=sha512`                  | for RSA keys
`withoutTLSCrypt=`               | any non-zero value disables `tls-crypt`
`pwgen='pwgen -s -c -n -y 32 1'` | a tool that will be executed to generate a password for CA private key
`subj='/CN=${cn}'`               | template for certificate subject, `${cn}` will be substituted
`type=`                          | selects `${type}_client_template.ovpn`<br> (for different VPNs (like tun and tap) on the same CA)<br> if omitted `client_template.ovpn` will be used

Subject example:
```
mail='root@local'
subj='/C=Country/ST=State/O=Organization/CN=${cn}/emailAddress=${mail}'
```


## Config files

`ovpn-ca.zsh` sources `config` file from the current directory
and from the server's directory. Any options can be specified there.
