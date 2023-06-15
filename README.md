# ovpn-ca.zsh


## A simple tool for OpenVPN CA

`ovpn-ca.zsh` generates CA, server secrets and ovpn client configs for OpenVPN in TLS mode.
A pretty simple tool.


## HOWTO

```
s=<vpn_name> ovpn-ca.zsh AddVPN
```

The `vpn_name` folder will be created with CA and server files.
CA private key will be encrypted with a password printed to stdout. Save it in a safe place!
Copy `sample_client_template.ovpn` into `vpn_name/client_template.ovpn` and edit it.
It's just a head that will be postpended with secrets to make a client's `.ovpn` file.


```
s=<vpn_name> c=<client_name> ovpn-ca.zsh AddClient
```

Put `_vpn_ca-cert.pem` and `-(cert|key|tlscrypt-key).pem` onto the server
and give `client@vpn_name.ovpn` to the client.


## Dependencies

`zsh openssl openvpn pwgen grep tree`
`openvpn` is used for `tls-crypt` only and isn't required when `withoutTLSCrypt=yes`
`pwgen` can be replaced with a similar tool


## Some options

```
s|server=<server>
c|client=<client>
```

Default values                   | Description
-------------------------------- | ---------------------------------
`y=1`                            | client certificate years of validity
`caYears=10`                     | CA certificate years of validity
`serverYears=10`                 | server certificate years of validity
`key=ed448`                      | other possible values: `ed25519`, `rsa:4096`
`digest=sha512`                  | for RSA keys
`withoutTLSCrypt=`               | any non-zero value disables `tls-crypt`
`pwgen='pwgen -s -c -n -y 32 1'` | a tool that will be executed to generate a password for the CA private key
`subj='/CN=${cn}'`               | template for the certificate subject, `${cn}` will be substituted
`type=`                          | selects `${type}_client_template.ovpn`<br> (for different VPNs (like tun and tap) on the same CA)<br> if omitted `client_template.ovpn` will be used

Subject example:
```
mail='root@local'
subj='/C=Country/ST=State/O=Organization/CN=${cn}/emailAddress=${mail}'
```


## Config files

`ovpn-ca.zsh` sources `config` file from the current directory
and from the server's directory. Any options can be specified there.


## Expiration

To list all certs expiration dates and days left:
```
s=<server> ShowAllCertsExpiration
```


## Revocation

Just create a file named as the client's serial number to revoke,
in <crls> directory configured as `crl-verify <crls> dir` on the OpenVPN server.
The file's content doesn't matter, though it is convenient to put the client's name there.

Get client's certificate serial number:
```
s=<server> c=<client> ovpn-ca.zsh ShowClientSerial
```

One-liner:
```
(export c=<client> s=<server>; ssh <vpn_server> "echo $c > /etc/openvpn/server/crls/$(ovpn-ca.zsh ShowClientSerial)")
```
