#!/bin/perl

use utf8;
use warnings;
use strict;

my $ns = 'en.';
my $wiki = 'memory-alpha.wikia.com';
my $api_url = 'http://'.$ns.$wiki.'/api.php';
my $export_url = 'http://'.$ns.$wiki.'/wiki/Special:Export';
my $aplimit = 500; # number of page names in one API request; passed to the API; 500 for anon, 1000 for logged in bot
my $pages_per_xml = 5000; # number of pages in one Special::Export request
my $current_only = 1;   # 1 = pages_current, 0 = pages_full

use Time::HiRes qw[time];
use LWP::UserAgent;
use LWP::ConnCache;
use HTTP::Request::Common;
use HTTP::Cookies;
use URI::Escape qw[uri_escape_utf8];
use HTML::Entities qw[decode_entities];

my $stm = time;

my $br = LWP::UserAgent->new;
$br->conn_cache(LWP::ConnCache->new());
$br->agent("ma_dump/1.2");
$br->cookie_jar(HTTP::Cookies->new(file => "cookies.txt", autosave => 1, ignore_discard => 1));

#my @namespaces = (0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 102, 103, 110, 111); # probably should fetch this list from somewhere
my @namespaces = (0); # just the main namespace

my @pages;
print "Getting page list...\n";
foreach my $ns (@namespaces) {
        my $apfrom;
        do {
                my $url = $api_url . "?action=query&list=allpages&apnamespace=$ns&aplimit=$aplimit&format=xml" .
                        ( $apfrom ? "&apfrom=$apfrom" : '' );

                undef $apfrom;
                my $res = $br->get($url);
                if ($res->is_success) {
                        push @pages, $res->decoded_content =~ m#<p pageid="\d+" ns="\d+" title="(.*?)" />#g;
                        ($apfrom) = $res->decoded_content =~ m#<allpages apfrom="(.*?)" />#;
                } else {
                        die $res->status_line." on $url";
                }

        } while defined $apfrom;
        print "Done with ns-$ns, now have ",scalar @pages," page(s).\n";
}

printf "%d page(s) to fetch, %d at a time, %d part(s) expected...\n", scalar @pages, $pages_per_xml, map( int( /^\d+$/ ? $_ : $_+1 ), @pages / $pages_per_xml );

my %export_parms = (
        action => 'submit',
        curonly => 1,
);
delete $export_parms{curonly} unless $current_only;

my $wiki_fn = $wiki;
$wiki_fn =~ s~[^\w\.\-]~_~g;

my $part = 0;
while (@pages) {
        $part++;

        $export_parms{pages} = join("\n", map(decode_entities($_), splice(@pages, 0, $pages_per_xml) ) );

        my $req = new HTTP::Request POST => $export_url;
        $req->content_type('application/x-www-form-urlencoded');
        $req->content( join('&', map(sprintf("%s=%s", $_, uri_escape_utf8($export_parms{$_}) ), keys %export_parms) ) );

        my $xml_file = sprintf "%s_pages_%s_hard_part%03d.xml", $wiki_fn, $export_parms{curonly} ? 'current' : 'full', $part;
        my $res = $br->request($req, $xml_file);

        if ($res->is_success) {
                print "OK. $xml_file ",-s $xml_file," bytes.\n";
        } else {
                die $res->decoded_content, "\n*** ", $res->status_line, "\n";
        }

}

print time-$stm," second(s). $part parts.\n";
