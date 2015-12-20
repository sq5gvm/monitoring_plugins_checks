## Example command configuration for icinga2
### Call monitoring
```
object CheckCommand "asterisk-calls" {
  import "plugin-check-command"

  command = [ CustomPluginDir + "/check_asterisk_calls.pl" ]
  arguments = {
    "-H" = "$host.vars.asterisk.ami_host$"
    "-P" = "$host.vars.asterisk.ami_port$"
    "-u" = "$host.vars.asterisk.ami_user$"
    "-s" = "$host.vars.asterisk.ami_pass$"
    "--callWarning" = {
           value = "$service.vars.callWarning$"
           set_if = "$service.vars.callWarning$".len
           }
    "--callCritical" = {
           value = "$service.vars.callCritical$"
           set_if = "$service.vars.callCritical$".len
           }
  }
}
```

### Queue monitoring
```
object CheckCommand "asterisk-queue" {
  import "plugin-check-command"

  command = [ CustomPluginDir + "/check_asterisk_queue.pl" ]
  arguments = {
    "-H" = "$host.vars.asterisk.ami_host$"
    "-P" = "$host.vars.asterisk.ami_port$"
    "-u" = "$host.vars.asterisk.ami_user$"
    "-s" = "$host.vars.asterisk.ami_pass$"
    "-q" = "$service.vars.queue$"
  }
}
```