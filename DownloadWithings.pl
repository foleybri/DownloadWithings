#!/usr/bin/perl
#use strict;
use warnings;

use JSON 2;
use LWP::Authen::OAuth2 0.19;
use LWP::Authen::OAuth2::ServiceProvider::Withings;
use POSIX qw(strftime);
use Excel::Writer::XLSX;
use Config::Simple;
use Carp;
use Term::ReadKey;
use File::Slurp;
# use LWP::ConsoleLogger::Everywhere ();

my $cfg         = new Config::Simple( 'config_private.cfg' );
my $tokens_file = 'tokens.txt';

if ( !-d $cfg->param( 'backup_location' ) ) {
    croak( $cfg->param( 'backup_location' ) . "does not exist\n" );
}

# Types:
# 1 : Weight (kg)
# 4 : Height (meter)
# 5 : Fat Free Mass (kg)
# 6 : Fat Ratio (%)
# 8 : Fat Mass Weight (kg)
# 9 : Diastolic Blood Pressure (mmHg)
# 10 : Systolic Blood Pressure (mmHg)
# 11 : Heart Pulse (bpm)
# 54 : SP02(%)
# 71 : Body Temperature
# 76 : Muscle Mass
# 77 : Hydration
# 88 : Bone Mass
# 91 : Pulse Wave Velocity

# The types that are available in my version of smart body analyser
my %types = (
    1  => 'weight',
    4  => 'height',
    5  => 'fat free mass',
    6  => 'fat ratio',
    8  => 'fat mass weight',
    11 => 'pulse',
);
my @type_keys = keys %types;
@type_keys = sort @type_keys;

# Attribute:
# 0 : The measuregroup has been captured by a device and is known to belong to this user (and is not ambiguous)
# 1 : The measuregroup has been captured by a device but may belong to other users as well as this one (it is ambiguous)
# 2 : The measuregroup has been entered manually for this particular user
# 4 : The measuregroup has been entered manually during user creation (and may not be accurate)r
# 5 : Measure auto, it's only for the Blood Pressure Monitor. This device can make many measures and computed the best value

my $saved_tokens;
if ( -f $tokens_file ) {
    $saved_tokens = read_file( $tokens_file );
}

my $oauth2 = LWP::Authen::OAuth2->new(
    service_provider => "Withings",
    client_id        => $cfg->param( 'clientid' ),
    client_secret    => $cfg->param( 'consumersecret' ),
    redirect_uri     => $cfg->param( 'redirect_uri' ),

    token_string => $saved_tokens,
    save_tokens => \&save_tokens,
);

# cache these in a file so we dont have to authorise against withings every time
sub save_tokens {
    my ( $token_string ) = @_;

    my $filename = $tokens_file;
    open( my $fh, '>', $filename ) or die "Could not open file '$filename' $!";
    print $fh $token_string;
    close $fh;

    print "saved new tokens!\n";
}

# If this is our first time, then do authorisation
if ( !$oauth2->can_refresh_tokens ) {
    my $url = $oauth2->authorization_url();
    print "Visit this URL: $url and paste the code here\n";

    my $code = '';
    ReadMode( 'noecho' );
    print "Enter Code: ";
    chomp( $code = <STDIN> );
    ReadMode( 'restore' );

    $oauth2->request_tokens( code => $code );
}

if ( $oauth2->should_refresh() ) {
    print "refreshing tokens\n";
    $oauth2->request_tokens();
}

my $res = $oauth2->get( 'https://wbsapi.withings.net/measure?action=getmeas&category=1' );

if ( !$res->is_success ) {
    die $res->status_line;
}

my $payload = JSON->new->decode( $res->decoded_content );

# Data is split into MeasureGroups.  However it seems that pulse always comes in its own measure group, even if weight, fat-free mass, etc was recorded at the same time.  We have special logic below to merge these two measure groups
my @groups = sort { $a->{ date } <=> $b->{ date } } @{ $payload->{ body }{ measuregrps } };

my %unique = ();
foreach my $group ( @{ $payload->{ body }{ measuregrps } } ) {
    $unique{ $group->{ date } }++;
}
my @dates = sort keys %unique;

printf( "Found %s results\n", scalar @dates );

my $workbook    = Excel::Writer::XLSX->new( $cfg->param( 'backup_location' ) . '/data.xlsx' );
my $worksheet   = $workbook->add_worksheet( 'Data' );
my $date_format = $workbook->add_format( num_format => 'yyyy-mm-dd HH:mm' );
$worksheet->set_column( 0, 0, 20 );
$worksheet->freeze_panes( 1, 0 );

my ( $row, $col, $last_recorded_height ) = ( 0, 0, 0 );

# Column Headers
$worksheet->write_string( $row, $col++, 'Date' );
$worksheet->write_string( $row, $col++, 'Attribute' );
for my $type_key ( @type_keys ) {
    $worksheet->write_string( $row, $col++, $types{ $type_key } );
}
$worksheet->write_string( $row, $col++, 'BMI' );

my $min_weight = 1000;
my $max_weight = 0;

# Data
for my $date ( @dates ) {
    $row++;
    $col = 0;
    my $this_weight = 0;
    my @groups      = grep { $_->{ date } eq $date } @{ $payload->{ body }{ measuregrps } };

    my @measures;
    foreach my $group ( @groups ) {
        push @measures, @{ $group->{ measures } };
    }

    $worksheet->write_date_time( $row, $col++, strftime( "%Y-%m-%dT%H:%M:%S", localtime( $date ) ), $date_format );
    $worksheet->write_number( $row, $col++, $groups[ 0 ]->{ attrib } );

    for my $type_key ( @type_keys ) {
        my ( $measure ) = grep { $_->{ type } == $type_key } @measures;
        if ( $measure ) {
            if ( $type_key == 4 ) {
                $last_recorded_height = $measure->{ value } * ( 10**$measure->{ unit } );
            }
            elsif ( $type_key == 1 ) {
                $this_weight = $measure->{ value } * ( 10**$measure->{ unit } );
            }

            if ( $type_key == 1 || $type_key == 5 ) {
                my $this = $measure->{ value } * ( 10**$measure->{ unit } );
                if ( $this < $min_weight ) { $min_weight = $this; }
                if ( $this > $max_weight ) { $max_weight = $this; }
            }

            # API says: Value for the measure in S.I units (kilogram, meters, etc.). Value should be multiplied by 10 to the power of "unit" (see below) to get the real value.
            $worksheet->write_number( $row, $col++, $measure->{ value } * ( 10**$measure->{ unit } ) );
        }
        else {
            $worksheet->write_blank( $row, $col++ );
        }
    }

    if ( $last_recorded_height > 0 && $this_weight > 0 ) {
        $worksheet->write_number( $row, $col++, $this_weight / ( $last_recorded_height**2 ) );
    }
}

# Charts
my $weight_chart = $workbook->add_chart( type => 'scatter', subtype => 'straight_with_markers', name => 'Weight Graph' );
$weight_chart->add_series( categories => [ 'Data', 1, $row, 0, 0 ], values => [ 'Data', 1, $row, 2, 2 ], name => 'Weight' );
$weight_chart->add_series( categories => [ 'Data', 1, $row, 0, 0 ], values => [ 'Data', 1, $row, 5, 5 ], name => 'Fat Free' );

$weight_chart->set_x_axis( name => 'Date', date_axis => 1, num_format => 'yyyy-mm-dd' );
$weight_chart->set_y_axis( name => 'kg', min => $min_weight, max => $max_weight );

my $bmi_chart = $workbook->add_chart( type => 'scatter', subtype => 'straight_with_markers', name => 'BMI Graph' );
$bmi_chart->add_series( categories => [ 'Data', 1, $row, 0, 0 ], values => [ 'Data', 1, $row, 8, 8 ], name => 'BMI' );
$bmi_chart->add_series( categories => [ 'Data', 1, $row, 0, 0 ], values => [ 'Data', 1, $row, 6, 6 ], name => 'Fat Ratio', y2_axis => 1 );

$bmi_chart->set_x_axis( name => 'Date', date_axis => 1, num_format => 'yyyy-mm-dd' );
$bmi_chart->set_y_axis( name => 'BMI' );
$bmi_chart->set_y2_axis( name => '%' );

$workbook->close();
