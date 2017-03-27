#!/usr/bin/perl
use strict;
use warnings;

use ZabbixAPI;
use Etsy::StatsD;
use Benchmark ':hireswallclock';

my $start = Benchmark->new;

my $hosts;
my $zab=ZabbixAPI->new("http://yourzabb.hostname.here/zabbix/");
$zab->login("your_zabb_api_user","your_zabb_api_pass");
my $statsd = Etsy::StatsD->new('127.0.0.1', '8125');

$hosts=$zab->host_get (
	{
		output => [ 'host', 'hostid', 'status' ]
	}
);

for my $host (@$hosts) {
	my $hostID = $host->{hostid};
	my $cleanHost = $host->{host};
	my $hostStatus = $host->{status};
	$cleanHost =~ s/ /_/g;
	print "$cleanHost: $hostID\n";

	my $host_items=$zab->item_get(
		{
			hostids => $hostID,
			output => 'extend'
		}
	);

	my $numSent = 0;
	for my $item (@$host_items){
		my $cleanItem = $item->{name};
		my @resolvers = ();
		if (@resolvers = $cleanItem =~ /\$([0-9])/g) {
			my $cleanKey = $item->{key_};	
			if ($cleanKey =~ /\[(.*)\]/) {
				my @keyArr = split(',', $1);
				foreach my $r (@resolvers) {
					my $resolved = $keyArr[$r - 1];
					$cleanItem =~ s/\$$r/$resolved/;
				}
			} else {
				print "parsing error for $cleanItem...\n";
			}
		}
		$cleanItem =~ s/_/-_-/g;
		$cleanItem =~ s/ /_/g;
		$cleanItem =~ s/\./-dot-/g;
		$cleanItem =~ s/\\/-bkslash-/g;
		$cleanItem =~ s/\//-frslash-/g;
		$cleanItem =~ s/\)/-rparen-/g;
		$cleanItem =~ s/\(/-lparen-/g;

		my $curVal = $item->{lastvalue};

		if ($hostStatus eq "1") {
			$curVal = "0";
		}
		
		my %d = ();
		%d = ( 'graphite_prefix.'.$cleanHost.'.'.$cleanItem => $curVal.'|g' );
			
		$statsd->send( \%d );
		$numSent++;

	}
	print($numSent." stats sent\n");
}

my $end = Benchmark->new;
my $diff = timediff($end, $start);
my %d = ( 'graphite_prefix.zabbpumper.walltime' => $diff->real.'|g' );
$statsd->send( \%d );
