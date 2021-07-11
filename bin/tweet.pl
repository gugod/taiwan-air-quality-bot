#!/usr/bin/env perl
use v5.26;
use utf8;
use feature 'signatures';

use Geo::Hash;
use Twitter::API;
use YAML ();
use Encode ('encode_utf8');
use Getopt::Long ('GetOptionsFromArray');
use Mojo::UserAgent;

exit(main(@ARGV));

sub main {
    my @args = @_;

    my %opts;
    GetOptionsFromArray(
        \@args,
        \%opts,
        'c=s',
        'y|yes'
    ) or die("Error in arguments, but I'm not telling you what it is.");

    maybe_tweet_update(\%opts, build_message() );

    return 0;
}

sub percentile95 (@nums) {
    my @sorted = sort { $a <=> $b } @nums;
    return $sorted[ @sorted / 100 * 95 ];
}

sub brick ($num) {
    # More-or-less the same as the legend from  https://v5.airmap.g0v.tw/
    ($num >= 70) ? "🟪" : # LARGE PURPLE SQUARE
    ($num >= 53) ? "🟥" : # LARGE RED SQUARE
    ($num >= 41) ? "🟨" : # LARGE ORANGE SQUARE
    ($num >= 35) ? "🟨" : # LARGE YELLOW SQUARE
    "🟩"                  # LARGE GREEN SQUARE
}

sub sorted {
    my @geohashes = @_;
    my $hasher = Geo::Hash->new;
    return map { $_->[0] } sort {
        $a->[1][0] <=> $b->[1][0] || # Lat: South first
        $b->[1][1] <=> $a->[1][1]    # Lng: East first
    } map { [$_, [ $hasher->decode($_) ] ] } @geohashes;
}

sub build_message {
    my $groups = air_quality_summarized_by_geohash4();
    my @bricks = map {
        brick(percentile95( map { $_->{"Data"}{"Dust2_5"} } @{ $groups->{$_} } ))
    } sorted(keys %$groups);
    return join("", @bricks) . "\n(PM2.5 熱度圖)";
}

sub air_quality_summarized_by_geohash4() {
    my $sites = Mojo::UserAgent->new()->get('https://api.airmap.g0v.tw/json/airmap.json')->result->json;
    my %groups;
    my $hasher = Geo::Hash->new;
    for my $site (@{ $sites }) {
        my $geohash = $hasher->encode(
            $site->{"LatLng"}{"lat"},
            $site->{"LatLng"}{"lng"},
            4,
        );
        push @{ $groups{$geohash} //= [] }, $site;
    }
    return \%groups;
}

sub maybe_tweet_update ($opts, $msg) {
    unless ($msg) {
        say "# Message is empty.";
        return;
    }

    my $config;

    if ($opts->{c} && -f $opts->{c}) {
        say "[INFO] Loading config from $opts->{c}";
        $config = YAML::LoadFile( $opts->{c} );
    } else {
        say "[INFO] No config.";
    }

    say "# Message";
    say "-------8<---------";
    say encode_utf8($msg);
    say "------->8---------";

    if ($opts->{y} && $config) {
        say "#=> Tweet for real";
        my $twitter = Twitter::API->new_with_traits(
            traits => "Enchilada",
            consumer_key        => $config->{consumer_key},
            consumer_secret     => $config->{consumer_secret},
            access_token        => $config->{access_token},
            access_token_secret => $config->{access_token_secret},
        );
        my $r = $twitter->update($msg);
        say "https://twitter.com/" . $r->{"user"}{"screen_name"} . "/status/" . $r->{id_str};
    } else {
        say "#=> Not tweeting";
    }
}
