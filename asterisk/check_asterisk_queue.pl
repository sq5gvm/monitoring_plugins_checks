#!/usr/bin/perl -w
# 
#     Copyright (C) 2015  Mirosław Lach
# 
#     This program is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 3 of the License, or
#     (at your option) any later version.
# 
#     This program is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
# 
#     You should have received a copy of the GNU General Public License
#     along with this program.  If not, see <http://www.gnu.org/licenses/>.
# 

use strict;
use warnings;
#use Data::Dumper;
use Monitoring::Plugin;
use Monitoring::Plugin::Threshold;
use Asterisk::AMI;

sub max ($$) { $_[$_[0] < $_[1]] }
sub min ($$) { $_[$_[0] > $_[1]] }

my $np = Monitoring::Plugin->new( shortname => "ASTERISK" );
$np = Monitoring::Plugin->new(usage => "Usage: %s [ -h|--help ]",);
$np->add_arg(
	spec => 'host|H=s',
	help => '-H <address>, --host=<address> AMI hostname or address',
	required => 1,
);
$np->add_arg(
	spec => 'port|P=s',
	help => '-P <number>, --port=<number> AMI port number (default: %s)',
	required => 1,
	default => "5038"
);
$np->add_arg(
	spec => 'user|u=s',
	help => '-u <username>, --user=<username> AMI username ',
	required => 1,
);
$np->add_arg(
	spec => 'secret|s=s',
	help => '-s <secret>, --secret=<secret> AMI secret',
	required => 1,
);

$np->add_arg(
	spec => 'queue|q=s',
	help => '-q <name>, --queue=<name> Asterisk queue name',
	required => 1,
);


$np->add_arg(
	spec => 'channelWarning=s',
	help => '--channelWarning=<THRESHOLD_DEF>',
);
$np->add_arg(
	spec => 'callWarning=s',
	help => '--callWarning=<THRESHOLD_DEF>',
);
$np->add_arg(
	spec => 'channelCritical=s',
	help => '--channelCritical=<THRESHOLD_DEF>',
);
$np->add_arg(
	spec => 'callCritical=s',
	help => '--callCritical=<THRESHOLD_DEF>',
);


$np->getopts;

my $astman = Asterisk::AMI->new(PeerAddr => $np->opts->host,
                                PeerPort => $np->opts->port,
                                Username => $np->opts->user,
                                Secret => $np->opts->secret
                                );

$np->plugin_exit( 3, "Unable to connect to asterisk") unless ($astman);

my $action = $astman->send_action({ Action => 'Command',
                                    Command => 'queue show '.$np->opts->queue
                                 });
my $response = $astman->get_response($action);

if ($response->{"GOOD"} != 1) {
	$np->plugin_exit( 3, "Error communicating with Asterisk. ". $response->{"Message"} );
}

#print $astman->amiver()."\n";

my $iCalls = 0;
my $iQueueLen = 0;
my $iDailyWaitAvg = 0;
my $iDailyTalkAvg = 0;
my $fCurrentWaitMax = 0;
my $fCurrentWaitAvg = 0;

my $iAgents = 0;
my $iAgentsTalking = 0;
my $iAgentsPaused = 0;
my $iW = 0;
my $iC = 0;
my $iA = 0;
my $fSLA = 0.0;


my $res = $response->{'CMD'};
my $iMode = 0;
my $queue = $np->opts->queue;
# header
if (@$res[0] =~ /^$queue has (\d*) calls \(max .*\) in '.*' strategy \((\d*)s holdtime, (\d*)s talktime\), W:(\d*), C:(\d*), A:(\d*), SL:([0-9.]*)% within \d*s/) {
	(undef, $iDailyWaitAvg, $iDailyTalkAvg, $iW, $iC, $iA, $fSLA) = (@$res[0] =~ m/^$queue has (\d*) calls \(max .*\) in '.*' strategy \((\d*)s holdtime, (\d*)s talktime\), W:(\d*), C:(\d*), A:(\d*), SL:([0-9.]*)% within \d*s/ );
}
for (my $i=1; $i<scalar(@$res); $i++) {
	$_ = @$res[$i];
	if (/^\s*Members:/) {
		$iMode = 1;
		next;
	}
	if (/^\s*(No Callers|Callers:)/) {
		$iMode = 2;
		next;
	}

	if ($iMode == 1) {
		$iAgents++;

		if ((/In use/) && !(/paused/)) {
			$iCalls++;
		}
		if (/In use/) {
			$iAgentsTalking++;
		}
		if (/paused/) {
			$iAgentsPaused++;
		}
	}
	if ($iMode == 2) {
		$iQueueLen++;
		my ($waitm, $waits) = m/\(wait: (\d*):(\d*), prio:/;
		$fCurrentWaitAvg += $waitm * 60;
		$fCurrentWaitAvg += $waits;

		$fCurrentWaitMax = max($fCurrentWaitMax, $waitm*60+$waits);
	}
#	print $iMode . ":" . @$res[$i]."\n";
}

$fCurrentWaitAvg = ($iQueueLen > 0) ? $fCurrentWaitAvg / $iQueueLen : 0;

$np->add_perfdata(
	label => "queue length",
	value => $iQueueLen,
	uom => "",
	threshold => Monitoring::Plugin::Threshold->set_thresholds(
		warning  => $np->opts->channelWarning,
		critical => $np->opts->channelCritical,
	),
);
$np->add_perfdata(
	label => "active calls",
	value => $iCalls,
	uom => "",
	threshold => Monitoring::Plugin::Threshold->set_thresholds(
		warning  => $np->opts->channelWarning,
		critical => $np->opts->channelCritical,
	),
);
$np->add_perfdata(
	label => "agents",
	value => $iAgents,
	uom => "",
	threshold => Monitoring::Plugin::Threshold->set_thresholds(
		warning  => $np->opts->callWarning,
		critical => $np->opts->callCritical,
	),
);
$np->add_perfdata(
	label => "agents paused",
	value => $iAgentsPaused,
	uom => "",
	threshold => Monitoring::Plugin::Threshold->set_thresholds(
		warning  => $np->opts->callWarning,
		critical => $np->opts->callCritical,
	),
);
$np->add_perfdata(
	label => "agents talking",
	value => $iAgentsTalking,
	uom => "",
	threshold => Monitoring::Plugin::Threshold->set_thresholds(
		warning  => $np->opts->callWarning,
		critical => $np->opts->callCritical,
	),
);

$np->add_perfdata(
	label => "daily waittime avg",
	value => $iDailyWaitAvg,
	uom => "s",
	threshold => Monitoring::Plugin::Threshold->set_thresholds(
		warning  => $np->opts->callWarning,
		critical => $np->opts->callCritical,
	),
);
$np->add_perfdata(
	label => "daily talktime avg",
	value => $iDailyTalkAvg,
	uom => "s",
	threshold => Monitoring::Plugin::Threshold->set_thresholds(
		warning  => $np->opts->callWarning,
		critical => $np->opts->callCritical,
	),
);
$np->add_perfdata(
	label => "queue waittime max",
	value => $fCurrentWaitMax,
	uom => "s",
	threshold => Monitoring::Plugin::Threshold->set_thresholds(
		warning  => $np->opts->callWarning,
		critical => $np->opts->callCritical,
	),
);
$np->add_perfdata(
	label => "queue waittime avg",
	value => $fCurrentWaitAvg,
	uom => "s",
	threshold => Monitoring::Plugin::Threshold->set_thresholds(
		warning  => $np->opts->callWarning,
		critical => $np->opts->callCritical,
	),
);

my $code = 0;
my @tests;
foreach my $perf ( @{ $np->perfdata } ){
#	print Dumper $perf->threshold;
	my $lcode = $np->check_threshold(
		check => $perf->value,
		warning => $perf->threshold->warning,
		critical => $perf->threshold->critical,
	);
	if ($lcode != 0) {
		push @tests, $perf->label;
	}
	$code = max($code, $lcode);
}

my $remarks = "";
$remarks = " Also threshold checks failed for: ".join(",", @tests) if ($#tests > 0);

$np->plugin_exit( $code, "Queue handles ".$iCalls." active and ".$iQueueLen." queued calls and has ".$iAgents." agents. ".$remarks ) if $code != OK;
$np->plugin_exit( $code, "Queue handles ".$iCalls." active and ".$iQueueLen." queued calls and has ".$iAgents." agents." );
