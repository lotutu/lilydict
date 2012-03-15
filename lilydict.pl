#!/usr/bin/perl
use warnings;
use strict;
use LWP::UserAgent;
use Term::ANSIColor ;
use XML::Simple;
use Data::Dumper;

use utf8;
binmode (STDOUT, ':utf8');
binmode (STDIN, ':utf8');
binmode (STDERR, ':utf8');

defined $ARGV[0] or &Usage and exit;

my %config;  #配置项存储在这个变量中

my $keyword=join(' ', @ARGV);
my $keyword_link=join('+', @ARGV);
my $keyword_file=$keyword_link . ".xml";

my ($word, $times, $lang, $def, @sents);

my (	$DictDir,  # 存放词典文件的目录
	$warn_times ); # 开始提醒的次数
my $url ;

&process_env_var;

# get the dictionary
# &test_local_dict  and print "file exists\n";
&test_local_dict  and &read_local_dict or &read_internet_dict;

# 输出到屏幕上
&output_to_screen;

# 存储文件
&output_to_local_file;


# &Debug;



sub read_config_file
{
	 # read config file to get user configure information
	defined $_[0] or warn " Need an argument in read_config_file ";
	my $configure_file=$_[0];
	open (my $RD, "<$configure_file") or return -1;
	binmode($RD, ':utf8');

	while(my $input=<$RD>)
	{
		chomp($input);
		$input =~ s/#.*$//;   # 清除注释
		$config{$1}=$2 if $input =~ m/^([^=]+)=([^=]+)$/;
	}
	close $RD;
}

sub process_env_var
{
	 # process environment variavles, also read config file and so on
	$DictDir="$ENV{HOME}/.lilydict";
	&load_default_set();
	&read_config_file("/etc/lilydict/conf/lilydict.cfg");
	&read_config_file("$ENV{HOME}/.lilydict/conf/lilydict.cfg");
	$warn_times = 3;
	$url = get_dict_cn_url($keyword);
}

sub get_dict_cn_url{
    my $word = shift;
    $word =~ s/ /+/g;
    return "http://www.dict.cn/ws.php?utf8=true&q=$word";
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
	@sents = @{$content->{sent}} if defined $content->{sent};
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
	$def=$xml_content->{def} if defined $xml_content->{def} or 
		# 没有找到解释的处理
		warn "Cannot find meaning\n" and exit;

#	sent 里面保存的是例句, 如果是多个例句则是数组引用，单个例句则为hash引用
	if (defined $xml_content->{sent}){
	    if (ref($xml_content->{sent}) eq "ARRAY"){
		@sents = @{$xml_content->{sent}} 
	    } elsif (ref($xml_content->{sent}) eq "HASH"){
	    	push @sents, $xml_content->{sent};
	    }
	} 
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
	print color $config{警告颜色};
	print "这个单词已经查询了$times 次\n" if $times >= $config{警告上限次数};

	print color $config{释义颜色};
	print  $def , "\n";
	print color "RESET";
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

sub load_default_set
{
# 这个函数为程序设计一些默认变量，优先级没有配置文件中的高 
	$config{警告上限次数}=3;
	$config{释义颜色}="RESET";
	$config{警告颜色}="RED";
	$config{例句颜色}="RESET";
	$config{例句释义颜色}="RESET";
	$config{词典目录}="$ENV{HOME}/.lilydict";
}


sub Debug
{
	while (@_ = each %config)
	{
		print "$_[0] = $_[1]\n";
	}
}

sub get_dict_file_path
{
# 这个函数根据要查询的单词名称来决定其词典文件的存储位置。
# 最初词典文件的存储位置是都在一个目录之中的，但是这样在
# 文件比较多的时候会使得查询比较慢。
# 暂时设置单词的存储位置为: 提取单词的前三个字母，分为两个子目录，
# 然后再加上单词本身。这样一来 active 就成了 a/c/t/active。
# 而对于那些不够三个字母的单词，就取其前两个或者前一个，根据其
# 长度决定

	defined $_[0] or print "Debug Information:\nNeed one argument in function get_dict_file_path\n";
	my $word=$_[0];
	my $path="";
	my @chars = split('', $word);
	my $count= scalar @chars;
	$count = $count < 3? $count: 3;
	for(my $i =0; $i<$count; $i++)
	{
		$path = $path . $chars[$i] . '/'
	}

	$path .= $word;
	return $path;
}

sub random_practice {
# 这个函数用来检验单词记忆成果, 机制是随机产生一些本地已经查询过的单词对用户进行测试
}


# 因为使用的都是全局变量，程序的修改有点复杂, 考虑是否应该使用结构体

sub practice_one_word{  # 参数为一个文件名,代表着词典文件
# 这个函数针对一个单词进行测试，是检测函数的子函数
    @_ > 0 or return -1;
    $keyword_file = shift @_; 
    $keyword_link = substr($keyword_file, 0,length($keyword_file) - 4);
    $keyword = $keyword_link; $keyword =~ s/\+/ /g;
    print "$keyword: ";
    read_local_dict();
    while(1){
	chomp (my $input = <STDIN>);
	if ($def =~ m/$input/){
	    print color "BOLD GREEN";
	    print "ok";
	    print color "RESET";
	    delete_dict_file($keyword);  # 已经记住的单词，可以删除了
	    last;
	} else {

	    print color "BOLD RED";
	    print "hmm, maybe you are wrong.\n ";
	    print color "RESET";

	    print "Retry?(no)";
	    chomp (my $option = <STDIN>);
	    $option = lc($option);

#	只认 yes Yes YES y Y 等等的表示认可的词语，其他的一律视为no
	    if ($option eq "y" or $option eq "yes"){
	    	print "Input your new try: ";
	    	next;
	    } else {
#		最后要输出词语的正确解释
		print "The correct answer is  $def\n";
	    }
	}
    }
}

sub delete_dict_file{
    @_ >0 or return -1;
    my $key_word = shift @_;
    my $path = get_dict_file_path($key_word);
    unlink $path;
    return 0;
}
