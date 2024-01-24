# Unity

Unity is a tool to generalise a number of actions and tools which ordinarily have a number of diverse and unique argument, paradigms, and syntaxes.


## Usage

Unity provides a prompt interface similar to that found in metasploit. The following generalised flow exists: **Protocols** have **Actions**, **Actions** have **Techniques**, and **Techniques** have **Variables**.

You can view all the available flows with `show all`, or show specifics such as a given protocol's available actions with `show actions`.

You can set the protocol either via the first argument to the program: `./unity.rb SMB`, or via the interactive `set` function:
```
|| () []> set protocol
```

The `set` function will present a prompt for you to chose from. You can `set` protocols, actions, techniques and variables.


`generate` will build the command for you, placing in a merged collection of your variables, and the defaults from the technique.

`run` will build the command and run it for you, as `generate` would.

As an example of a full walkthrough:

```
❯ ./unity.rb
|| () []> set protocol
Select Protocol > SMB
|SMB| () []> set action
Select Action > Find Open Shares
|SMB| (Find Open Shares) []> set technique
Select Technique > smbclient (smbclient -N -L \\\\%{ip}) [*****]
|SMB| (Find Open Shares) [smbclient]> set ip 10.0.0.1
|SMB| (Find Open Shares) [smbclient]> generate
smbclient -N -L \\\\10.0.0.1
```

Some Techniques have default variables which can be overriden. You can view the technique's configuration via `show vars`:

```ruby
{
     :current_protocol => "DNS",
       :current_action => "Subdomain Enumeration",
    :current_technique => {
             :name => "dnsrecon",
          :command => "dnsrecon -D %{in_file} -d %{domain} -t brt -c %{out_file}",
         :priority => nil,
        :iteration => nil
    },
            :variables => {},
    :default_variables => {
         :in_file => "/usr/share/dnsrecon/namelist.txt",
        :out_file => "./dnsrecon_brute.csv"
    }
}
```

In the above, we only need to set `domain` via `set domain example.com` for the function to work as expected.
