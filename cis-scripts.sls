{% if grains['os_family'] == 'RedHat' and grains['osrelease'].startswith('6') %}

## Copy CIS scripts:
# Moved to cis-scripts.sls so it can be run separately
# Much of cis.sls will not run with test=True without
# the existence of these scripts.
cis_copy_scripts:
  file:
    - recurse
    - name: /opt/cis/scripts
    - source: salt://cis/scripts
    - file_mode: 755
    - dir_mode: 700
    - template: jinja
    - clean: True

{% endif %}
