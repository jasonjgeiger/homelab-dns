# Documentation
# https://lunarwatcher.github.io/posts/2020/05/14/setting-up-ssl-with-pihole-without-a-fqdn.html

# Meta: certificate locations
# The certificate for the site
cert=crt.pem
# The private key for the site
certPk=pk.pem
# The Certificate Authority (CA) certificate
ca=ca.crt.pem
# The CA private key
caPk=ca.pk.pem

# Replace the host with whatever URL you chose.
# If you're using pihole.lan too, this line doesn't need to be changed.
host={$1}

# This defines how long the cert is valid.
# This can be redefined, but I personally keep it at 365 days.
# Since this requires renewing, and not regenerating, this script
# is only useful for the initial generation, or re-creating the
# entire thing, if you feel like it.
certValidityDays=365

# Create a CA
openssl req -newkey rsa:4096 -keyout "${caPk}" -x509 -new -nodes -out "${ca}" \
  -subj "/OU=Unknown/O=Unknown/L=Unknown/ST=unknown/C=AU" -days "${certValidityDays}"

# Create a Cert Signing Request
openssl req -new -newkey rsa:4096 -nodes -keyout "${certPk}" -out csr.pem \
       -subj "/CN=${host}/OU=Unknown/O=Unknown/L=Unknown/ST=unknown/C=AU"

# Sign the certificate
openssl x509 -req -in csr.pem -CA "${ca}" -CAkey "${caPk}" -CAcreateserial -out "${cert}" \
       -days "${certValidityDays}"

# See the official post; it requires the private and public key merged into a combined file
cat "${certPk}" "${cert}" | tee ./combined.pem