#!/usr/bin/perl


# Retrieve Segmentation Rules from the WhatCounts API.
#
# Note that this script is used in conjunction with some PHP code
#   to autopopulate a CCK dropdown menu.  It's 'machine-readable name'
#   needs to be "wcsend_segmentation_rule", it should be a select list 
#   that is *required*.  And under the "PHP code" section of the 
#   "Allowed values list:", you should have the PHP code that is at the 
#   end of this file.



use strict;
use LWP::UserAgent;

my $web_api_url     = 'https://premiere.whatcounts.com/bin/api_web';
my $web_api_realm = 'media_alliance';
my $web_api_pass  = '';
my $web_api_command = 'show_segments';

my $url="$web_api_url?r=$web_api_realm&p=$web_api_pass&cmd=$web_api_command";


# Run the web API call.
my $web_browser = LWP::UserAgent->new;
my $response = $web_browser->post($url);
my $seg_menu = { 0 => '(no segmentation)' };

if ($response->is_success) {   # ie. the HTTP request itself worked.
  my $content = $response->content;

  if ($content =~ /^\d/) {

    my @results = split(/\s*\n\s*/, $content);
    foreach (@results) {
      my ($seg_id, $seg_name) = /^(\d+)\s*(.+)\s*/;
      print "$seg_id|$seg_name\n";
    }
  }
  else{
    print "-1|ERROR!  The wcsend module can't get segmentation rules from WC.  Results came in unexpected format: '$content'";
  }

}
else {
    print "-1|ERROR!  The wcsend module can't get segmentation rules from WC.  HTTP request to WC API failed.";
}


##############################################

__END__




////////////////
//  The following is **PHP** code, not Perl.
// 
//  It is for use in one of Drupal's CCK drop-downs, in conjunction with the above perl script.
//  See the comment at the top of this file, for more on what to do with it.
////////////////

// Recycle a perl script that we'd written to get this same info for Bricolage.

$full_path_to_segmentation_script =
         $_SERVER['DOCUMENT_ROOT'] . base_path()
         . drupal_get_path('module', 'wcsend')
         . '/segmentation_menu.pl';

exec ($full_path_to_segmentation_script, $output, $return);

$return_array[0] = "(no segmentation)";  #Default value.

foreach ($output as $row) {
    $a = split('\|', $row);  # Split on the '|' (pipe) character.
    $return_array[$a[0]] = $a[1];
}
return $return_array;

