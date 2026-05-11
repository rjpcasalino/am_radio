#!/usr/bin/env perl
# UTF-8 handling tests for am_radio.pl

use strict;
use warnings;
use utf8;
use Test::More tests => 18;
use Encode qw(encode_utf8 decode_utf8);

binmode STDOUT, ':encoding(UTF-8)';
binmode STDERR, ':encoding(UTF-8)';

# Test 1-2: Script has UTF-8 support enabled
my $script_content = do {
    local $/;
    open my $fh, '<:encoding(UTF-8)', '../am_radio.pl' or die "Cannot open am_radio.pl: $!";
    <$fh>;
};
like($script_content, qr/use utf8;/, 'Script uses utf8 pragma');
like($script_content, qr/binmode STDOUT.*encoding\(UTF-8\)/, 'Script sets UTF-8 output encoding');

# Define the functions to test (extracted from am_radio.pl)
sub pad_to {
    my ($str, $len) = @_;
    my $current = length($str);
    return $str . (' ' x ($len - $current)) if $current < $len;
    return $str;
}

sub truncate_to {
    my ($str, $len) = @_;
    return $str if length($str) <= $len;
    return substr($str, 0, $len - 1) . '…';
}

# Test 3-5: Test pad_to with Chinese characters
{
    my $chinese = '美国中文电台';
    my $padded = pad_to($chinese, 20);
    is(length($padded), 20, 'pad_to pads Chinese characters to correct length');
    like($padded, qr/^美国中文电台\s+$/, 'pad_to preserves Chinese characters and adds spaces');
    my $chinese_count = () = $padded =~ /[\x{4e00}-\x{9fff}]/g;
    is($chinese_count, 6, 'pad_to preserves all 6 Chinese characters');
}

# Test 6-9: Test truncate_to with Japanese characters
{
    my $japanese = '日本のラジオ放送局名前が長い';
    my $truncated = truncate_to($japanese, 10);
    is(length($truncated), 10, 'truncate_to truncates Japanese to correct character length');
    like($truncated, qr/^日本/, 'truncate_to preserves beginning Japanese characters');
    like($truncated, qr/…$/, 'truncate_to adds ellipsis');

    # Test that short strings aren't truncated
    my $short_japanese = '日本語';
    my $not_truncated = truncate_to($short_japanese, 10);
    is($not_truncated, '日本語', 'truncate_to does not truncate short strings');
}

# Test 10-12: Test with emoji
{
    my $emoji = '🎵 Radio 🎶';
    my $emoji_padded = pad_to($emoji, 15);
    is(length($emoji_padded), 15, 'pad_to handles emoji correctly');
    like($emoji_padded, qr/🎵/, 'pad_to preserves first emoji');
    like($emoji_padded, qr/🎶/, 'pad_to preserves second emoji');
}

# Test 13-14: Test mixed Latin, Chinese, and emoji
{
    my $mixed = 'KEXP Seattle 西雅图 🎵';
    my $truncated = truncate_to($mixed, 20);
    ok(length($truncated) <= 20, 'truncate_to handles mixed Latin/Chinese/emoji correctly');

    my $mixed_short = 'KEXP 西雅图';
    my $padded = pad_to($mixed_short, 20);
    is(length($padded), 20, 'pad_to handles mixed content correctly');
}

# Test 15-16: Test station name parsing with UTF-8
{
    my $station = '美国中文电台-西雅图::http://example.com/stream';
    my ($name, $url) = split /::/, $station, 2;
    is($name, '美国中文电台-西雅图', 'Station parsing preserves UTF-8 names');
    is($url, 'http://example.com/stream', 'Station parsing correctly splits UTF-8 entries');
}

# Test 17: Test that character length (not byte length) is used
{
    my $str = '日本';  # 2 characters, 6 bytes in UTF-8
    is(length($str), 2, 'length() counts characters not bytes for UTF-8');
}

# Test 18: Test substr with UTF-8
{
    my $str = '美国中文电台';  # 6 characters
    my $sub = substr($str, 0, 3);
    is($sub, '美国中', 'substr() works with character positions in UTF-8');
}

done_testing();
