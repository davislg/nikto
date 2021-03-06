#!/usr/bin/perl
#VERSION,2.00
use Getopt::Long;
Getopt::Long::Configure('no_ignore_case');

###############################################################################
#                               Nikto                                         #
# --------------------------------------------------------------------------- #
#                       last update: 11.10.2007                               #
# --------------------------------------------------------------------------- #
###############################################################################
#  Copyright (C) 2004-2007 CIRT, Inc.
#
#  This program is free software; you can redistribute it and/or
#  modify it under the terms of the GNU General Public License
#  as published by the Free Software Foundation; version 2
#  of the License only.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program; if not, write to the Free Software
#  Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
#
# Contact Information:
#  	Sullo (sullo@cirt.net)
#  	http://www.cirt.net/
#######################################################################
# See the README.txt and/or help files for more information on how to use & config.
# See the LICENSE.txt file for more information on the License Nikto is distributed under.
#
# This program is intended for use in an authorized manner only, and the author
# can not be held liable for anything done with this program, code, or items discovered
# with this program's use.
#######################################################################
# global var/definitions
my $STARTTIME = localtime();
use vars qw/$TEMPLATES %ERRSTRINGS %VERSIONS %CLI %VARIABLES %TESTS $CONTENT %FILES $CURRENT_HOST_ID $CURRENT_PORT/;
use vars qw/%REALMS %REALMS_TESTED %NIKTOCONFIG %NIKTO %OUTPUT %SERVER %request %result %COUNTERS/;
use vars qw/@KB_MSGS %db_extensions %FoF %UPDATES $DIV %TARGETS @DBFILE @SERVERFILE @BUILDITEMS $PROXYCHECKED/;

# setup
$DIV               = "-" x 75;
$NIKTO{version}    = "2.00";
$NIKTO{name}       = "Nikto";
$NIKTO{configfile} = "config.txt";    ### Change this line if your setup is having trouble finding it
$http_eol="\r\n";

# read the --config option
{
    my %optcfg;
    Getopt::Long::Configure('pass_through', 'noauto_abbrev');
    GetOptions(\%optcfg, "config=s");
    Getopt::Long::Configure('nopass_through', 'auto_abbrev');
    if (defined $optcfg{'config'}) { $NIKTO{configfile} = $optcfg{'config'}; }
}

load_configs();
find_plugins();
require "$NIKTO{plugindir}/nikto_core.plugin";       ### Change this line if your setup is having trouble finding it
nprint("T:$STARTTIME: Starting","d");
require "$NIKTO{plugindir}/nikto_reports.plugin";    ### Change this line if your setup is having trouble finding it
require "$NIKTO{plugindir}/nikto_single.plugin";     ### Change this line if your setup is having trouble finding it
require "$NIKTO{plugindir}/LW2.pm";                  ### Change this line if your setup is having trouble finding it
# use LW2;					     ### Change this line to use a different installed version

($a,$b) = split(/\./, $LW2::VERSION);
die("- You must use LW2 2.4 or later\n") if($a != 2 || $b < 4);

general_config();
load_databases();
load_databases('u');

LW2::http_init_request(\%request);
$request{'whisker'}->{'ssl_save_info'}              = 1;
$request{'whisker'}->{'lowercase_incoming_headers'} = 1;
$request{'whisker'}->{'timeout'}                    = $CLI{timeout} || 10;
if ($CLI{evasion} ne "") { $request{'whisker'}->{'encode_anti_ids'} = $CLI{evasion}; }
$request{'User-Agent'}         = $NIKTO{useragent};
$request{'whisker'}->{'retry'} = 0;
proxy_setup();

open_output();
nprint($DIV);
print "- $NIKTO{name} $NIKTO{version}/$NIKTO{core_version}     -     www.cirt.net\n";

set_targets();

$PROXYCHECKED = 0;    # only do proxy_check once

# actual scan for each host/port
foreach $CURRENT_HOST_ID (sort { $a <=> $b } keys %TARGETS)
{
    LW2::http_reset();
    $COUNTERS{hosts_completed}++;
    @KB_MSGS = ();
    if (($CLI{findonly}) && ($COUNTERS{hosts_completed} % 10) eq 0) { nprint("($COUNTERS{hosts_completed} of $COUNTERS{hosts_total})"); }

    ($TARGETS{$CURRENT_HOST_ID}{hostname}, $TARGETS{$CURRENT_HOST_ID}{ip}, $TARGETS{$CURRENT_HOST_ID}{display_name}) = resolve($TARGETS{$CURRENT_HOST_ID}{ident});
    if ($TARGETS{$CURRENT_HOST_ID}{ident} eq "") { next; }
    port_scan($TARGETS{$CURRENT_HOST_ID}{ports_in});

    # make sure we have open ports on this target
    if (keys(%{$TARGETS{$CURRENT_HOST_ID}{ports}}) eq 0)
   	{ nprint("+ No HTTP(s) ports found on $TARGETS{$CURRENT_HOST_ID}{ident} / $TARGETS{$CURRENT_HOST_ID}{ports_in}","","kb"); }

    $request{'whisker'}->{'host'} = $TARGETS{$CURRENT_HOST_ID}{hostname} || $TARGETS{$CURRENT_HOST_ID}{ip};

    foreach $CURRENT_PORT (keys %{ $TARGETS{$CURRENT_HOST_ID}{ports} })
    {
        if ($CURRENT_PORT eq "") { next; }
        $request{'whisker'}->{'port'}    = $CURRENT_PORT;
        $request{'whisker'}->{'ssl'}     = $TARGETS{$CURRENT_HOST_ID}{ports}{$CURRENT_PORT}{ssl};
        $request{'whisker'}->{'version'} = $NIKTOCONFIG{DEFAULTHTTPVER};
        if ($NIKTOCONFIG{'STATIC-COOKIE'} ne "") { $request{'Cookie'} = $NIKTOCONFIG{'STATIC-COOKIE'}; }

        get_banner();

        if ($CLI{findonly})
        {
            my $protocol = "http";
            if ($TARGETS{$CURRENT_HOST_ID}{ports}{$CURRENT_PORT}{banner} eq "")
            {
                $TARGETS{$CURRENT_HOST_ID}{ports}{$CURRENT_PORT}{banner} = "(no identification possible)";
            }
            if ($TARGETS{$CURRENT_HOST_ID}{ports}{$CURRENT_PORT}{ssl}) { $protocol .= "s"; }
            nprint("+ Server: $protocol://$TARGETS{$CURRENT_HOST_ID}{display_name}:$CURRENT_PORT\t$TARGETS{$CURRENT_HOST_ID}{ports}{$CURRENT_PORT}{banner}");
        }
	else 
	{
            dump_target_info();
            %FoF = ();
            $TARGETS{$CURRENT_HOST_ID}{total_vulns} = 0;
            auth_check();
            check_cgi();
            set_scan_items();
            map_codes();
            run_plugins();
            test_target();
	}

        write_kbase(next_kbase_id());
        write_output();
    }
}

nprint("+ $COUNTERS{hosts_total} host(s) tested");
send_updates();
close_output();
nprint("T:" . localtime() . ": Ending","d");
exit;

#################################################################################
####                Most code is now in nikto_core.plugin                    ####
#################################################################################
# load config file
sub load_configs
{
    open(CONF, "<$NIKTO{configfile}") || print STDERR "- ERROR: Unable to open config file '$NIKTO{configfile}' ($!), only 1 CGI directory defined.\n";
    my @CONFILE = <CONF>;
    close(CONF);

    foreach my $line (@CONFILE)
    {
        $line =~ s/\#.*$//;
        chomp($line);
        $line =~ s/\s+$//;
        $line =~ s/^\s+//;
        if ($line eq "") { next; }
        my @temp = split(/=/, $line, 2);
        if ($temp[0] ne "") { $NIKTOCONFIG{ $temp[0] } = $temp[1]; }
    }

    # add CONFIG{CLIOPTS} to ARGV if defined...
    if ($NIKTOCONFIG{CLIOPTS} ne "")
    {
        my @t = split(/ /, $NIKTOCONFIG{CLIOPTS});
        foreach my $c (@t) { push(@ARGV, $c); }
    }
    return;
}
#################################################################################
# find plugins directory
sub find_plugins
{
    # get the correct path to 'plugins'
    # if defined in config.txt file...
    if ($NIKTOCONFIG{EXECDIR} ne "")
    {
        if (-d "$NIKTOCONFIG{EXECDIR}/plugins") { $NIKTO{plugindir} = "$NIKTOCONFIG{EXECDIR}/plugins"; }
        $NIKTO{execdir} = $NIKTOCONFIG{EXECDIR};
    }

    if ($NIKTO{plugindir} eq "")
    {
        # try pwd?
        my $EXECDIR = "";
        if (-d "$ENV{PWD}/plugins")
        {
            $EXECDIR = $ENV{PWD};
        } else
        {
            $EXECDIR = $0;
            chomp($EXECDIR);
            $EXECDIR =~ s/nikto.pl$//;
            $EXECDIR =~ s/\/$//;
        }

        if ($EXECDIR eq "")
        {
            $EXECDIR = "./";
        }    # last ditch
        $NIKTO{plugindir}   = "$EXECDIR/plugins";
        $NIKTO{templatedir} = "$EXECDIR/templates";
        $NIKTO{execdir}     = "$EXECDIR";
    }

    if (!(-d $NIKTO{plugindir}))
    {
        print STDERR "I can't find 'plugins' directory. I looked around:\n";
        print STDERR "\t$CONFIG{PLUGINDIR}\n\t$ENV{PWD}\n\t$0\n";
        print STDERR "Try: switch to the 'nikto' base dir, or\n";
        print STDERR "Try: set PLUGINDIR in config.txt\n";
        exit;
    }

    $NIKTO{kbase} = "$NIKTO{execdir}/kbase/nikto.kbase";    ### Change this line if you would like to use another KB

    return;
}
#################################################################################
