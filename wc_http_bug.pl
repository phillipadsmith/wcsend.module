#!/usr/bin/perl


# This script is to test for a problem where if you tried to change the HTML part of a template
#    and if your html included the text "http://" anywhere in it, the templateEdit() command would 
#    fail with a null return-code.  If you run this script and you get "Response is '0'.", then it
#    worked.  "Response is ''." means the problem is still here.
#
# As of May 15, 2009, this seems to not be a bug anymore.




use strict;
use Data::Dumper;



# endpoint/license for SOAP API.
our  $endpoint = 'https://premiere.whatcounts.com/webservices/WhatCountsAPI';
our  $license = '';





# Set up for SOAP API calls.
use SOAP::Lite;

use constant API_RESPONSE_OK => 0;
use constant API_RESPONSE_FAILURE => 1;
use constant TEMPLATE_PART_SUBJECT => 0;
use constant TEMPLATE_PART_DESCRIPTION => 1;
use constant TEMPLATE_PART_NOTES => 2;
use constant TEMPLATE_PART_PLAINTEXT => 3;
use constant TEMPLATE_PART_HTML => 4;
use constant TEMPLATE_PART_AOL => 5;
use constant TEMPLATE_PART_WAP => 6;

my $rc;  #Return code.

# Get service object.
my $soap = SOAP::Lite->uri('urn:webservices.api.whatcounts')->proxy($endpoint);
# Getting session key...
my $licenseParam = SOAP::Data->name("license" => $license);
my $session = $soap->beginSession($licenseParam)->result();




my $changetemplate_html = <<END_HTML;
Here is some nice http:// <i>HTML</i>.
END_HTML

my $template_name = 'Test for development of wcsend Drupal module';



$rc = $soap->templateEdit($session, $template_name, TEMPLATE_PART_HTML,      $changetemplate_html)->result();  
$rc == API_RESPONSE_OK  || die "Couldn't change template html in template '$template_name'.";
print "Response is '$rc'.\n";



