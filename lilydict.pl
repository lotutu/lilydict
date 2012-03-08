#!/usr/bin/perl

# 现在还在开发之中，lilydict v0.07 ，目标是重写lilydict v0.06, 使得各个部分
# 的功能函数化，同时准备开发一个根据现在单词向用户询问的学习软件

use warnings;
use strict;
use LWP::UserAgent;
use Term::ANSIColor qw(:constants);
use XML::Simple;
use Data::Dumper;

use utf8;
binmode (STDOUT, ':utf8');
binmode (STDIN, ':utf8');

defined $ARGV[0] or &Usage and exit;

my $keyword=join(' ', @ARGV);
my $keyword_link=join('+', @ARGV);
my $keyword_file=$keyword_link . ".xml";

my ($word, $times, $lang, $def, @sents);

my (	$DictDir,  # 存放词典文件的目录
		$warn_times,  # 开始提醒的次数
		);
my $url;
# get the dictionary
&process_env_var;
# &test_local_dict  and print "file exists\n";
&test_local_dict  and &read_local_dict or &read_internet_dict;

&output_to_screen;

&output_to_local_file;

sub read_config_file
{
	 # read config file to get user configure information
	defined $_[0] or warn " Need an argument in read_config_file ";
	my $configure_file=$_[0];
}

sub process_env_var
{
	 # process environment variavles, also read config file and so on
	$DictDir="$ENV{HOME}/.lilydict";
	$warn_times = 3;
	&read_config_file("$DictDir/config");
	$url="http://www.dict.cn/ws.php?utf8=true&q=$keyword_link";
}

sub test_local_dict
{
	# test if there's a local dictionary file in local dictionary directory. 
	return 1 if -e  "$DictDir/$keyword_file" ;
	0;
}

sub get_internet_dict
{
	# if there's no local dictionary file, get one from internet
	my $ua = LWP::UserAgent->new;
	my $req = HTTP::Request->new(GET => $url);
	my $result = $ua->request($req);
	if($result->is_success)
	{
		$_[0] = $result->content;
	}
	else
	{
		die "找不到要查询的内容";
	}
}

sub read_local_dict
{
	# if there's a local dictionary file,  read dictionary file to get informations
	my $content=XMLin("$DictDir/$keyword_file");
	$word=$keyword;
	$times=$content->{times} + 1;
	$def=$content->{def};
#	print $content->{sent}, "\n";
	@sents = @{$content->{sent}};
	$lang = $content->{lang};
}

sub read_internet_dict
{
	# read the internet dictionary if there's no one at local disk
	my $content;
	&get_internet_dict($content) or die "Cannot get internet dictionary";  # get dictionary from the internet
	
	my $xml_content=XMLin($content);
	$word=$keyword;
	$times=1;
	$def=$xml_content->{def} if defined $xml_content->{def};
	@sents = @{$xml_content->{sent}} if defined $xml_content->{sent};
	my $tmpcount = scalar @sents;
	while($tmpcount --)
	{
		$sents[$tmpcount]->{orig} =~ s/<\/?em>//g;
	}
	$lang = $xml_content->{lang} if defined $xml_content->{lang};;
}

sub output_to_screen
{
	# output the dictionary information to stdout
	print "这个单词已经查询了$times 次\n" if $times >= $warn_times;
	print  $def , "\n";
}

sub output_to_local_file
{
	# write the dictionary to local disk
	open (my $WD, ">$DictDir/$keyword_file") or  warn "Cannot open file $DictDir/$keyword_file to write" and return ;
	binmode ($WD , ':utf8');
	print $WD "<?xml version=\"1.0\" encoding=\"utf-8\" ?>\n";
	print $WD "<dict>\n";
	print $WD "\t<word>$word</word>\n";
	print $WD "\t<def>$def</def>\n";
	print $WD "\t<times>$times</times>\n";
	print $WD "\t<lang>$lang</lang>\n";

	my $tmpcount = scalar @sents;
	if($tmpcount >0)
	{
		while($tmpcount --)
		{
			print $WD "\t<sent><orig>$sents[$tmpcount]->{orig}</orig>";
			print $WD "<trans>$sents[$tmpcount]->{trans}</trans></sent>\n";
		}
	};
	print $WD "</dict>\n";
	close $WD;
}

sub remove_local_dict
{
	 # remove local dictionary files
	unlink "$DictDir/$_[0]";
}

sub Usage
{
	print "Usage: $0 <words>\n";
	print "\twords can be either a single word  or an expression such as \"such as\"\n";
}
