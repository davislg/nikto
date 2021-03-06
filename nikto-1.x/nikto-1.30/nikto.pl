#!/usr/bin/perl
use Getopt::Long;
Getopt::Long::Configure('no_ignore_case');

# INSTALLED LW:
#use LW; 
# LOCAL LW:
require "./plugins/LW.pm";

#######################################################################
# last update: 05.30.2003
# --------------------------------------------------------------------#
#                               Nikto                                 #
# --------------------------------------------------------------------#
# This copyright applies to all code included in this distribution.
#
# Copyright (C) 2001-2003 Sullo/CIRT.net
#
# This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2  of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with this program; if not, write to the 
# Free Software Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
#
# Contact Information:
#  Sullo (sullo@cirt.net)
#  http://www.cirt.net/
#######################################################################
# See the README.txt and/or help files for more information on how to use & config.  
# See the LICENSE.txt file for more information on the License Nikto is distributed under.
#
# This program is intended for use in an authorized manner only, and the author
# can not be held liable for anything done with this program, code, or items discovered
# with this program's use.
#######################################################################
# global var/definitions
use vars qw/@OPTS %CLI %VARIABLES $CONTENT $ITEMCOUNT @COOKIES %FILES $CURRENT_HOST_ID $CURRENT_PORT/;
use vars qw/%CONFIG %NIKTO %OUTPUT %METHD %RESPS %INFOS %SERVER %request %result %JAR %DATAS/;
use vars qw/$DIV $VULS $OKTRAP $HOST %TARGETS @DBFILE @SERVERFILE @BUILDITEMS $PROXYCHECKED/;

# setup
$NIKTO{version}="1.30";
$NIKTO{name}="Nikto";
$DIV = "-" x 75;
my $STARTTIME=localtime();
&load_configs;
&find_plugins;
require "$NIKTO{plugindir}/nikto_core.plugin";

&general_config;

LW::http_init_request(\%request);
&proxy_setup;

&open_output;
nprint($DIV);
print "- $NIKTO{name} $NIKTO{version}/$NIKTO{core_version}     -     www.cirt.net\n";

&set_targets;
&load_scan_items;
$PROXYCHECKED=0; # only do proxy_check once

# actual scan for each host/port
foreach $CURRENT_HOST_ID (keys %TARGETS)
 {
  if (&host_config) { next; }  # find ports only, move on to next host
  foreach $CURRENT_PORT ( keys %{$TARGETS{$CURRENT_HOST_ID}{ports}} )
   {
    if ($CURRENT_PORT eq "") { next; }
#    nprint($DIV);
    $request{'whisker'}->{'host'}=$TARGETS{$CURRENT_HOST_ID}{ip};
    $request{'whisker'}->{'port'}=$CURRENT_PORT;
    $request{'whisker'}->{'ssl'}=$TARGETS{$CURRENT_HOST_ID}{ports}{$CURRENT_PORT}{ssl};
    $request{'whisker'}->{'lowercase_incoming_headers'}=1;
    $request{'whisker'}->{'http_ver'}=$CONFIG{DEFAULTHTTPVER};
    $request{'whisker'}->{'timeout'}=$CLI{timeout} || 10;
    $request{'User-Agent'} = $NIKTO{useragent};
    $request{'whisker'}->{'anti_ids'}=$CLI{evasion};
    $request{'Host'}=$CLI{vhost} || $TARGETS{$CURRENT_HOST_ID}{hostname} || $TARGETS{$CURRENT_HOST_ID}{ip};
    if ($CONFIG{'STATIC-COOKIE'} ne "") { $request{'Cookie'} = $CONFIG{'STATIC-COOKIE'}; }
    $VULS=0;

    &proxy_check;
    &dump_target_info;
    &check_responses;
    &check_cgi;
    &set_scan_items;
    &run_plugins;
    &test_target;
   }
 }

&close_output;
exit;

#################################################################################
####                 Most functions moved to core.plugin                     ####
#################################################################################
# load config file
sub load_configs
{
 my $configfile="config.txt";
 my $noconfig=0;
   open(CONF,"<$configfile") || $noconfig++;
   my @CONFILE=<CONF>;
   close(CONF);

 if ($noconfig) { print "- No config.txt file found, only 1 CGI directory defined.\n"; }

  foreach my $line (@CONFILE)
   {
    $line =~ s/\#.*$//;
    chomp($line);
    $line =~ s/\s+$//;
    $line =~ s/^\s+//;
    if ($line eq "") { next; }
    my @temp=split(/=/,$line,2);
    if ($temp[0] ne "") { $CONFIG{$temp[0]}=$temp[1]; }
   }

 # add CONFIG{CLIOPTS} to ARGV if defined...
 if ($CONFIG{CLIOPTS} ne "")
  {
   my @t=split(/ /,$CONFIG{CLIOPTS});
   foreach my $c (@t) { push(@ARGV,$c); }
  }
  return;
}

#################################################################################
# find plugins directory
sub find_plugins
{
 # get the correct path to 'plugins'
 # if defined in config.txt file...
 if ($CONFIG{PLUGINDIR} ne "")
  {
   if (-d $CONFIG{PLUGINDIR}) { $NIKTO{plugindir}=$CONFIG{PLUGINDIR}; }
  }
 
 if ($NIKTO{plugindir} eq "")
  { 
   # try pwd?
   my $NIKTODIR="";
   if (-d "$ENV{PWD}/plugins") { $NIKTODIR="$ENV{PWD}/"; }
   elsif (-d "plugins") { $NIKTODIR=""; }
   else
   {
    my $EXECDIR=$ENV{_};
    chomp($EXECDIR);
    $EXECDIR =~ s/nikto.pl$//;
    if ($EXECDIR =~ /(perl|perl\.exe)$/) { $EXECDIR=""; }  # executed as 'perl nikto.pl' ...
    if (-e "$EXECDIR/plugins") { $NIKTODIR="$EXECDIR/"; }
   }
   $NIKTO{plugindir}="$NIKTODIR"; $NIKTO{plugindir} .= "plugins";
  }

  if (!(-d $NIKTO{plugindir}))
  {
   print "I can't find 'plugins' directory. ";
   print "I looked in \& around:\n\t$ENV{PWD}\n\t$ENV{_}\n";
   print "Try switching to the 'nikto' directory so that the plugins dir can be found.\n";
   exit;
  }
 $FILES{dbfile}="$NIKTO{plugindir}/scan_database.db";
 $FILES{userdbfile}="$NIKTO{plugindir}/user_scan_database.db"; 
 $FILES{serverdbfile}="$NIKTO{plugindir}/servers.db"; 
return;
}
#################################################################################
