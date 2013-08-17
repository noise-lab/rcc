#!/usr/bin/perl

use CGI::Pretty qw/:standard :html3/;
use CGI::Carp  qw(fatalsToBrowser);
use Data::Dumper;

use strict;

my $c = new CGI;
my $this = $c->url(-relative=>1);
my $params = $c->Vars();

my $mailprog = "/usr/sbin/sendmail";
my @recipient_arr = ("feamster\@lcs.mit.edu");
my $recipient = join (",", @recipient_arr);

sub print_headers {
    my ($title) = @_;
    print header, start_html("$title"), h3("$title");
}

sub print_greeting { print "Thanks for agreeing to try the BGP
    configuration verifier.  Your request will be sent only to Nick
    Feamster, and your information will be kept entirely private.  We
    may contact you directly for feedback at some later date, but we
    won't spam you about unrelated issues. <p> We hope you will agree
    to be on a discussion email list for the verifier, but this is
    entirely opt-in.  We intend the list to be for providing useful
    feedback and discussion about feature requests, bug reports,
    etc.\n"; }

sub print_fb_greeting { print "Thanks for sending us your feedback.
    Your comments will be sent only to Nick Feamster, and your
    information will be kept entirely private. <p>\n"; }


sub print_form {

    my ($type) = @_;
    
    print start_form;
    if (!$type) {
	print table ({-border=>'0'},
		     Tr({-align=>'LEFT',-valign=>'TOP'},
			[
			 td(["First Name",textfield('first')]),
			 td(["Last Name",textfield('last')]),
			 td(["email address",textfield('email')]),
			 td(["Affiliation",textfield('affiliation')]),
			 td(["Function",popup_menu('function',
						   ['network operator',
						    'researcher',
						    'developer', 'other'],
						   'network operator')]),
			 td(["Add me to a<br>discussion list.",
			     popup_menu('discussion',
					['yes',
					 'no'], 'no')]),
			 td(["CVS Access",
			     popup_menu('cvs',
					['read-only',
					 'read-write'], 'read-only')]),
			 td(["Comments", textarea(-name=>'comments',
						  -default=>'',
						  -rows=>10,
						  -columns=>60)])
			 ])
		     );
    } else {
	print table ({-border=>'0'},
		     Tr({-align=>'LEFT',-valign=>'TOP'},
			[
			 td(["First Name",textfield('first')]),
			 td(["Last Name",textfield('last')]),
			 td(["email address",textfield('email')]),
			 td(["Affiliation",textfield('affiliation')]),
			 td(["Function",popup_menu('function',
						   ['network operator',
						    'researcher',
						    'developer', 'other'],
						   'network operator')]),
			 td(["Add me to a<br>discussion list.",
			     popup_menu('discussion',
					['yes',
					 'no'], 'no')]),
			 td(["Comments", textarea(-name=>'comments',
						  -default=>'',
						  -rows=>10,
						  -columns=>60)])
			 ])
		     );

    }

    print p;
    print hidden(-name=>'form_type', -default=>'access') if !$type;
    print hidden(-name=>'form_type', -default=>'feedback') if $type;
    print submit(-value=>'Submit'), reset, p;
    print end_form;
}

sub check_inputs {

    if ($params->{'email'} !~ /\w+\@\w+\.\w+/) {

	print "<font color=red><b>Please enter a real email address ($params->{'email'} is not valid.).</b></font><br>";
	&print_form();

	return 0;
    } elsif ($params->{'first'} eq '') {

	print "<font color=red><b>Please enter your first name.</b></font><br>";
	&print_form();

	return 0;
    } elsif ($params->{'last'} eq '') {

	print "<font color=red><b>Please enter your last name.</b></font><br>";
	&print_form();

	return 0;
    }
    return 1;
}


sub send_email {

    my ($email_name) = @_;

    my $subject = "Feedback";
    if ($params->{'form_type'} eq 'access') {
	$subject = "Request for CVS Access";
    }

     open (MAIL, "| $mailprog $recipient") || die "Unable to open $mailprog:$!\n";
     select(MAIL);
     
     print "From: $email_name\n";
     print "To: $recipient\n";
     print "Subject: [rcc] $subject\n";
     
     foreach (keys %{$params}) {
	 printf "%s = %s\n", $_, $params->{$_};
     }
     
     close(MAIL);
}


sub print_thanks {

    my ($email_name) = @_;

    my $item = "feedback";
    if ($params->{'form_type'} eq 'access') {
	$item = "request";
    }
    my $subject = "Feedback";
    if ($params->{'form_type'} eq 'access') {
	$subject = "Request for CVS Access";
    }

    
    printf ("<b>Thanks for your $item, %s.</b> <br> We will respond shortly.<p>",
	    $params->{'first'});

    print "<pre>\n";
    print "From: $email_name\n";
    print "To: $recipient\n";
    print "Subject: [rcc] $subject\n<p>";
    foreach (keys %{$params}) {
	printf "%s = %s\n", $_, $params->{$_};
    }
    print "</pre>\n";
}


sub print_footers{
    print end_html;
}


if (defined($params->{'email'})) {
    &print_headers();
    my $res = &check_inputs();

    if ($res) {

	my $first = $params->{'first'};
	my $last = $params->{'last'};
	my $email = $params->{'email'};
	my $email_name = "$first $last <$email>";

	&print_thanks($email_name);
	&send_email($email_name);
    }

} elsif ($params->{'subject'} eq 'access') {
    &print_headers("BGP Verification -- Request for CVS Access");
    &print_greeting();
    &print_form(0);
} else {
    &print_headers("BGP Verification -- Feedback");
    &print_fb_greeting();
    &print_form(1);
}

&print_footers();
