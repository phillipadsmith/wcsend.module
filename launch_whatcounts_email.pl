#!/usr/bin/perl


# This script is called from the wcsend module.  Really, this should be rewritten in PHP,
#   but we had already done it in Perl for a similar purpose with Bricolage.  So for now,
#   it is perl that is called from a sort of Drupal "wrapper".
#  
#
# You call this script with a "--url=" command-line param.  That URL we grab, and use
#   to update a WhatCounts list and template.  
#
# A bunch of other params are passed in via the content of the page itself.
#   We look for a section that looks like this:
#
#	                           
#<!--
#----start wcsend params----
#  changelist_from_name = Test on production!  (for may 14)  # You can put comments in with the '#' symbol.
#  changelist_from_email = testing_production@
#  changetemplate_subject = February 4th, 2009
#  changetemplate_plain_text = This is not really used at the moment-- we are converting HTML to plain text to get this value
#  segmentation_id = 0
#  list_id = 36467
#  template_id = 129064
#  format = 99     # -1=subscriber, 1=text, 2=html, 99=Multi-part MIME
#----end wcsend params----
#-->
#
# In Drupal, you set these params via the *theme*.
#
# Besides the params listed above, there are many more that you can set.  You'll
#   have to read through the code below to find them all, however.  :-(
#


use strict;
no strict "refs";



use Encode;
use SOAP::Lite;
use Getopt::Long;
use LWP::UserAgent;
use Data::Dumper;
use HTML::FormatText::WithLinks;
use LWP::UserAgent;



# When setting these vars via ${'varname'} = 'foo',
#   if you use "my $varname" rather than "our $varname", it seems to mess it up.
#   So we use "our".

our  $list_id;       # Who to send to.  This is the only param that is mandatory.
  
our  $template_id;   # What to send.  If undef, will use the default one for the list.
  
  
# Things you can change in the template.  
our  $changetemplate_subject;
our  $changetemplate_plain_text;


# Things to change in the list.
our  $changelist_from_name;   
our  $changelist_from_email;  

our  $changelist_replyTo_name;
our  $changelist_replyTo_email;

our  $changelist_errorsTo_name;
our  $changelist_errorsTo_email;


# endpoint/license for SOAP API.
our  $endpoint = 'https://premiere.whatcounts.com/webservices/WhatCountsAPI';
our  $license = '';


## Web API info-- needed for the actual *send*, since the SOAP send command doesn't seem to work.

# use the non-secure API.  
#  Otherwise, it chokes (for Rabble) with 'client-ssl-warning' => 'Peer certificate not verified'.
our  $web_api_url   = "http://premiere.whatcounts.com/bin/api_web";
our  $web_api_realm = 'media_alliance';
our  $web_api_pass  = '';


# The following web-API params are optional.

our  $segmentation_id;
## Your segmentation-ID, or use 0 for no segmentation.

our  $format;
### Message-send format.
### -1 for Subscriber specified (based upon their subscription record)
###  1  for Plain-text
###  2  for HTML
### 99  for Multipart MIME

our  $campaign_alias;
## A name that shows up in the report for your running of this list *this time*.
##   eg. 'My Test Campaign Alias'

our  $target_rss;
## Not sure what this does, or how to test if it works.  Should be 0 or 1

our  $notify_this_email_upon_completion;
## Send an email to this addr indicating that "emailing is complete".
##   eg. 'your_email@address.com'


#  The following are more things that the API may or may not let you modify in the list.
#    See my comments inline. 
#    (And try searching this script for 'fromAddress' for an example of how to change any of these.)

    # "listId"      -- Probably shouldn't try to change this.
    # "name"        -- The list's name.   Works in api
    # "description" -- The list's descr.  Works in api
    # "templateId"  -- The list's default template.  Works in api

    # 'trackingBaseUrl'.  -- Not sure if this works.  This does get saved, but it doesn't appear to show up in the list's web UI.

    # "trackHtmlReads", aka the 'Opens' checkbox.  Works.
    # "trackClickThroughs"... works.

    # The following are for the "Courtesy email" section...
      # "for new sign-ups"...
      #      "sendSignupAck"        
      #      "signupTemplateId"     
      # "after cancellation"...  aka unsubscribe.
      #      "sendCancelAck"        
      #      "cancelTemplateId"     

    # These change the "landing pages" for "subscribe" (aka 'new sign-up') and "unsubscribe" (aka 'cancel').
    #        "externalSignupLink"  
    #        "externalCancelLink"

    # 'optIn' means 'Require list sign-ups to be confirmed'.  It works.
    # 'optOut' saves its value, but doesn't appear to show up in the UI.
    # 'wrapPlainText' doesn't work.
    # 'wrapHtml' doesn't work.
    # 'multipart' doesn't work.
    # 'useAol' saves its value, but doesn't appear to show up in the UI.


###############################################################################################



# Get the command line switch "--url=..."
my $url;
GetOptions (
  'url=s'  => \$url,
);


# Get the webpage indicated in $url.

my $ua = LWP::UserAgent->new;
$ua->timeout(10);
my $response = $ua->get($url);
$response->is_success || die $response->status_line;
my $content =  $response->decoded_content;


# Go through the requested page, line by line, looking for the key=value pairs in the 
#   "----start/end wcsend params----" section.

my $edited_content =  '';

my $in_params_section = 0;  
my $wc_params;
my $title_block_subject;

foreach my $line (split(/\s*\n\s*/, $content)) {
        if ($line =~ m#<title>(.*)</title>#i) {
                $title_block_subject = $1;   # This is not actually used anymore.
        }
        elsif ($line =~ m#----(start|end) wcsend params----#) {
		# Set this when we enter the "----start/end wcsend params----", turn it off when we leave it.
                $in_params_section =  $1 eq 'start';
        }
        else {
                if ($in_params_section) {
			#  Format:  key=value   #with possible comment after it.
                        if ($line =~ /^\s*([^#]+?)\s*=\s*([^#]*)/) {
				my $key = $1;
				my $val = $2;
				$val =~ s/\s*$//g;  # trim any space off the end.
                                $wc_params->{$key} = $val;
                        }
                }
                else {
		  # $line =~ s#http://#https://#ig;  # A stupid hack to avoid the 'http://' bug in the WC template-HTML-change bug.
                  $edited_content .= "$line\n";
                }
        }
}

# For each param of this form:
#    $wc_params->{'param_name'} = 'param val';
# make it in to a 'normal' variable, like this:
#    $param_name = 'param val';

my ($key, $value);
while (($key, $value) = each(%$wc_params)){
  ${$key} = $value;
}


# What we will set the HTML part of the template to:
#   (The "%% smartget $url %%" is a whatcounts macro, meaning "get the HTML from this URL".)
my $changetemplate_html = "%% smartget $url %%";


# For the plain-text version of the mailout, we convert it programmatically here, from HTML.

my $html_converter = HTML::FormatText::WithLinks->new(
	before_link => '',
	after_link => ' [ %l ]',
	footnote => '',
	base => $url
);

$changetemplate_plain_text = $html_converter->parse($edited_content);








###############################################################################################




  # This script:
  #  - first changes some values in the list
  #  - then changes some values in the template
  #  - then launches the list, with some more params that you can set.


  # Check for the (only) mandatory param.
  if (! defined $list_id) {
    print "You have to provide a list_id for your mailing (who to send to).";
    exit 1;
  }  

  # Set up for Web API calls.
  my $web_api_login_url = "$web_api_url?r=$web_api_realm&p=$web_api_pass";

  
  # Set up for SOAP API calls.

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

  # Get session key, and start session.
  my $licenseParam = SOAP::Data->name("license" => $license);
  my $session = $soap->beginSession($licenseParam)->result()
	  ||  all_finished({'success' => 0,  'message' => "Couldn't connect to WhatCounts via 'SOAP'."});


  ####### Modify the list.  ####### 


  # Get the current settings for the list.
  my $list_data = $soap->listGetDataById($session, $list_id)->result()
	  ||  all_finished({'success' => 0,  'message' => "Couldn't get list data for list_id '$list_id'."});

  # Here is what is typically in $list_data:

  # $VAR1 = bless( {
  #                 'fromAddress' => '',
  #                 'replyToAddress' => '',
  #                 'errorsToAddress' => '',
  #
  #                 'listId' => '36425',
  #                 'name' => 'z_ Dan test list',
  #                 'description' => 'A list for testing WC/Bricolage integration',
  #                 'templateId' => '128941',
  #
  #                 'trackingBaseUrl' => '',
  #                 'trackHtmlReads' => 1,
  #                 'trackClickThroughs' => 1,
  #
  #                 'vmta' => '',
  #
  #                 'signupTemplateId' => '-1',
  #                 'cancelTemplateId' => '-1',
  #                 'externalSignupLink' => '',
  #                 'externalCancelLink' => '',
  #                 'sendSignupAck' => 0,
  #                 'sendCancelAck' => 0,
  #
  #                 'optIn' => 0,
  #                 'optOut' => 0
  #                 'wrapPlainText' => 0,
  #                 'wrapHtml' => 0,
  #                 'multipart' => 0,
  #                 'useAol' => 0,
  #      }, 'WhatCountsAPIList' );


  # Change any of the email addresses ("from", "replyTo", or "errorsTo").
  #   Note:  If a name is provided but no email, the name will be discarded 
  #          and nothing will be changed.

  if ($changelist_from_email) {
    if ($changelist_from_name) {
      $list_data->{'fromAddress'}     = qq("$changelist_from_name" <$changelist_from_email>);
    }else{
      $list_data->{'fromAddress'}     = $changelist_from_email;
    }
  }
  
  if ($changelist_replyTo_email) {
    if ($changelist_replyTo_name) {
      $list_data->{'replyToAddress'}  = qq("$changelist_replyTo_name" <$changelist_replyTo_email>);
    }else{
      $list_data->{'replyToAddress'}  = $changelist_replyTo_email;
    }
  }
  
  if ($changelist_errorsTo_email) {
    if ($changelist_errorsTo_name) {
      $list_data->{'errorsToAddress'} = qq("$changelist_errorsTo_name" <$changelist_errorsTo_email>);
    }else{
      $list_data->{'errorsToAddress'} = $changelist_errorsTo_email;
    }
  }
  

  # To have the change take effect, you have to put the data-structure back together as follows (according to
  #    an email we got from a competent WC tech):

  my $data = SOAP::Data->name("list" =>
    \SOAP::Data->value(
          SOAP::Data->name("fromAddress"          => $list_data->{"fromAddress"})->type("xsd:string"),
          SOAP::Data->name("replyToAddress"       => $list_data->{"replyToAddress"})->type("xsd:string"),
          SOAP::Data->name("errorsToAddress"      => $list_data->{"errorsToAddress"})->type("xsd:string"),

          SOAP::Data->name("listId"               => $list_data->{"listId"}),  # Probably shouldn't try to change this.
          SOAP::Data->name("name"                 => $list_data->{"name"}),      #works in api
          SOAP::Data->name("description"          => $list_data->{"description"}),   #works in api
          SOAP::Data->name("templateId"           => $list_data->{"templateId"}),    #works in api

          # 'trackingBaseUrl' saves its value, but doesn't appear to show up in the UI.
          SOAP::Data->name("trackingBaseUrl"      => $list_data->{"trackingBaseUrl"})->type("xsd:string"),  
          # "trackHtmlReads", aka the 'Opens' checkbox.  Works.
          SOAP::Data->name("trackHtmlReads"       => $list_data->{"trackHtmlReads"})->type("xsd:boolean"), 
          # "trackClickThroughs"... works.
          SOAP::Data->name("trackClickThroughs"   => $list_data->{"trackClickThroughs"})->type("xsd:boolean"), 

          # The following are for the "Courtesy email" section...
            # "for new sign-ups"...
          SOAP::Data->name("sendSignupAck"        => $list_data->{"sendSignupAck"})->type("xsd:boolean"),
          SOAP::Data->name("signupTemplateId"     => $list_data->{"signupTemplateId"}),
            # "after cancellation"...  aka unsubscribe.
          SOAP::Data->name("sendCancelAck"        => $list_data->{"sendCancelAck"})->type("xsd:boolean"),
          SOAP::Data->name("cancelTemplateId"     => $list_data->{"cancelTemplateId"}),

          # These change the "landing pages" for "subscribe" (aka 'new sign-up') and "unsubscribe" (aka 'cancel').
          SOAP::Data->name("externalSignupLink"   => $list_data->{"externalSignupLink"})->type("xsd:string"),  #subscribe
          SOAP::Data->name("externalCancelLink"   => $list_data->{"externalCancelLink"})->type("xsd:string"),  #unsubscribe

          # 'optIn' means 'Require list sign-ups to be confirmed'
          SOAP::Data->name("optIn"                => $list_data->{"optIn"})->type("xsd:boolean"), 
          # 'optOut' saves its value, but doesn't appear to show up in the UI.
          SOAP::Data->name("optOut"               => $list_data->{"optOut"})->type("xsd:boolean"),
          # 'wrapPlainText' doesn't work.
          SOAP::Data->name("wrapPlainText"        => $list_data->{"wrapPlainText"})->type("xsd:boolean"),
          # 'wrapHtml' doesn't work.
          SOAP::Data->name("wrapHtml"             => $list_data->{"wrapHtml"})->type("xsd:boolean"),
          # 'multipart' doesn't work.
          SOAP::Data->name("multipart"            => $list_data->{"multipart"})->type("xsd:boolean"),
          # 'useAol' saves its value, but doesn't appear to show up in the UI.
          SOAP::Data->name("useAol"               => $list_data->{"useAol"})->type("xsd:boolean"),
          )
  );

  # Commit the changes to the list.
  $rc = $soap->listUpdate($session, $list_id, $data)->result();
  $rc == API_RESPONSE_OK && $rc ne ''  
  	||  all_finished({'success' => 0,  'message' => "Couldn't update list $list_id. Return code was '$rc'."});



  ####### Change the template. #########

  # Either a template_id was passed in to us, or we get the default one for the list.
  if (! defined $template_id) {
    $template_id = $list_data->{'templateId'};  
  }  
  
  # Look up the name of the template; we need this for calls to SOAP's templateEdit().
  my $template_name;
  $rc = get_template_name_from_id($template_id, $web_api_login_url);
  if ($rc->{'error'}) {
     print "Can't find name for template with ID '$template_id':  $rc->{error}";
     exit 1;
  }
  else { # no error
    $template_name = $rc->{'name'};
  }

  # Need to encode strings-- otherwise, if they contain special chars (eg. left quotes or japanese yen symbol), SOAP will choke.
  my $encoded_subject   = SOAP::Data->type(string => $changetemplate_subject   );
  my $encoded_plaintext = SOAP::Data->type(string => $changetemplate_plain_text);
  my $encoded_html      = SOAP::Data->type(string => $changetemplate_html      );

  $rc = $soap->templateEdit($session, $template_name, TEMPLATE_PART_SUBJECT,   $encoded_subject  )->result();   
  $rc == API_RESPONSE_OK && $rc ne ''
  	|| all_finished({'success' => 0,  'message' => "Couldn't change template subject in template '$template_name'.  Return code was '$rc'."});

  $rc = $soap->templateEdit($session, $template_name, TEMPLATE_PART_PLAINTEXT, $encoded_plaintext)->result(); 
  $rc == API_RESPONSE_OK && $rc ne ''
  	|| all_finished({'success' => 0,  'message' => "Couldn't change template plaintext in template '$template_name'.  Return code was '$rc'."});

  $rc = $soap->templateEdit($session, $template_name, TEMPLATE_PART_HTML,      $encoded_html     )->result();  
  $rc == API_RESPONSE_OK && $rc ne ''
  	|| all_finished({'success' => 0,  'message' => "Couldn't change template html in template '$template_name'.  Return code was '$rc'."});



  ###### Launch the list. ########
  

  # I don't know why this SOAP method wasn't working for me.  Use WebAPI instead.
      # $rc = $soap->listRun($session, $sender, $notify_email, $list_id, $template_id, $segmentation_id, $format, $test_only);
      # exit;

  # Set up the array that will be passed to the Web API list_run command:

  my @web_api_login = ( 
    'realm' => $web_api_realm,
    'pwd'   => $web_api_pass,
  );

  my @web_api_params_to_run_list = (
    'cmd'     => 'launch',  
    'list_id' => $list_id,  
    'template_id' => $template_id,
  );

  if (defined $segmentation_id)
    { push @web_api_params_to_run_list, 'segmentation_id' => $segmentation_id; }   

  if (defined $format)
    { push @web_api_params_to_run_list, 'format' => $format; }   

  if (defined $campaign_alias)
    { push @web_api_params_to_run_list, 'campaign_alias' => $campaign_alias; }

  if (defined $target_rss)
    { push @web_api_params_to_run_list, 'target_rss' => $target_rss; }

  if (defined $notify_this_email_upon_completion)
    { push @web_api_params_to_run_list, 'notify_email' => $notify_this_email_upon_completion; }


  # Create web-browser agent and run the web API call.
  my $web_browser = LWP::UserAgent->new;
  my $response;

  # WC API currently (2009-march16) has a bug whereby launching a list will fail, but if you try again, it will work.
  #  So we check here for failure, and try a couple more times if it doesn't work the first time.
  my $attempts=0;
  while ($attempts++ < 3) {
    # print "Here goes attempt # $attempts...";
    $response = $web_browser->post($web_api_url, [@web_api_login, @web_api_params_to_run_list]);
    # Check if the web request worked, but the API returned 'FAILURE'.
    if ($response->is_success  &&  $response->content =~ /^FAILURE/) {
      #print "Sleep and repeat:  content was '".$response->content."'.";
      sleep 2;  # Pause and repeat.
    }else{
      #print "Looks good!  ";
      last;  # Done.
    }
  }

  # Report back to the bricolage template that called us.
  my $send_result;
  if ($response->is_success) {   # ie. the HTTP request itself worked.
    $send_result->{'success'} = $response->content =~ /^SUCCESS/;    # The text returned contains 'SUCCESS', or not.
    $send_result->{'message'} = $response->content;     # If success -> results, else -> error_msg.
  }else {
    $send_result->{'success'} = 0;
    $send_result->{'message'} = "Even the HTTP request didn't work.";
  }

  all_finished($send_result);

############

  
  # all_finished() is a lazy routine.  
  #   Rather than calling "all_finished($result)", I used to "return $result;", and 
  #   $result (a whole data structure) was returned to Bricolage.
  #
  #   Now we are returning to the wcsend Drupal module, and it has slightly different requirements.

  sub all_finished {
    print $_[0]->{'message'};
    exit ! $_[0]->{'success'};  # exit 0 == success, exit 1 == problem.
  }


  sub get_template_name_from_id {

    my $wanted_id = shift;
    my $web_api_login_url = shift;   # Need to have this passed in, because we can't access locally scoped outside vars.
    
    my $templates = {};
   
    
    my $web_browser = LWP::UserAgent->new;
    my $response = $web_browser->post("$web_api_login_url&cmd=show_templates");
    if (!$response->is_success) {   
      return {'error'=>"HTTP request didn't work.\n"};
    }
    else { # success
      my $content = $response->content;

      # A good call will return rows, each with a template number followed by template name.  
      #  All error messages that I could find do *not* start with a number.  So test for that...
      if ($content !~ /^\d/) {
        return {'error'=>"Error:  '$content'."};
      }
      else{
        my @results = split(/\s*\n\s*/, $content);   # split on newlines
        foreach (@results) {
          my ($template_id, $template_name) = /^(\d+)\s+(.+)\s*/;
          $templates->{$template_id} = $template_name;
        }

        if ($templates->{$wanted_id}) {
          return { 'name' => $templates->{$wanted_id} };
        }
        else {
          return {'error'=>"Couldn't find a name for template number '$wanted_id'."};
        }
      }
    }
  }
