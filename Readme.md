# amazon-cloudwatch-installer

An install script for installing and running aws cloudwatch with user-level permissions, with sane configuration. Specifically, this install targets rpm-based linux distros such as UW-IT's managed CentOS offering.

## Why this installer?

The [on-prem install instructions](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/install-CloudWatch-Agent-on-first-onprem.html) are cumbersome, incomplete and sometimes even wrong. The linked zip file contains an rpm that has config for systemd but nothing for initd. Already that was something we would have to cook up.

The instructions have you generate a json file with a wizard, and then hand-edit that json file. Then with each startup, it will translate that json into _another_ json file, which it then translates into a toml file. It is this toml file that has various config such as where the credentials are located. This arrangement portends a unique json config per environment. Rather than go that route, we generate the toml directly per-host.

This installer facilitates updates to the installer or our config so we can add it as a step in our deployment playbook. We also unpack the rpm, take the useful stuff and toss the rest, and we install it to a location that the user controls. Finally, we have option `--add-cron` to add to the user's crontab for startup.

## Installation instructions

This script was built to be run as a one-line curl command. One thing it expects is for the credentials file to already exist. You can add a file of the following format to your credential location (defaulted to `/data/local/etc/amazon-cloudwatch-credentials`)...
```
[AmazonCloudWatchAgent]
aws_access_key_id = AKIA****
aws_secret_access_key = ****
```

Having set up your credentials file, installation is simply a matter of doing...
```
./install.sh --add-cron
```

This can be a one-time thing, but can also be rerun to pick up new changes. Whether it be to pick up a new cloudwatch agent or to add files to watch on.

## Possible issues

It's impossible to tell what version of cloudwatch you're running until after you've installed it, but it's possible that amazon will change their toml schema and break us in a future update. The version of the cloudwatch agent running on our servers is currently `1.201929.0`. I can't imagine their setup will look anything like this if they were to ever fully bake their on-prem offering of cloudwatch.