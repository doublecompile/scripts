#!/usr/bin/perl
######################################################################
# Copyright 2008–2016 @doublecompile
#
# MIT License
#
# This was a handy little script created by @doublecompile.
# Its intent is to make very easy the addition of a virtual host
# to a shared hosting setup.
######################################################################

use Getopt::Long;
use File::Copy;
use Pod::Usage;

my $man = 0;
my $help = 0;
my $o_host = '';
my $o_user = '';
my $o_dir = '/var/web';
my $o_templates = '/usr/share/vhost-boss/templates';
my $o_cache = '/var/lib/vhost-boss';

GetOptions(
	'help|?' => \$help, man => \$man,
        "host=s" => \$o_host,
        "user=s"   => \$o_user,
        "directory=s"  => \$o_dir,
        "templates=s" => \$o_templates,
        "cache\s" => \$o_cache
	) or pod2usage(2);
pod2usage(1) if $help;
pod2usage(-exitval => 0, -verbose => 2) if $man;

if ( !$o_host || !$o_user ) {
    print "Wait, I can't make a site without a domain name and a user.\n";
    print "Try running the script with the domain and user you need, ya jerk!\n";
    print "You need an example? Sheesh, what do I look like? Ah, fine.\n";
    print "Try \"vhost-boss --host example.com --user exampleuser\"\n";
    exit;
}

# A subroutine to... you guessed it. Check for dir, else mkdir then chown.
sub mkdirAcl {
    my($dir, $mod, $uid, $gid) = @_;
    unless(-e $dir or mkdir($dir, $mod)){
        die "Unable to create directory $dir. $!";
    }
    chown($uid, $gid, $dir) or die "Unable to chown. $!";
}

######################################################################
# Check that the folder doesn't already exist
######################################################################

my $basedir = $o_dir;
my $vhost = $o_host;
my $vhostu = $vhost =~ s/./_/r;
my $user = $o_user;
my $homedir = "$basedir/$user";
my $vhostdir = "$homedir/$vhost";
my $templatedir = $o_templates;
my $cachedir = $o_cache;

print "$vhost? One site... comin' up!\n";
print "Gonna put it in $basedir\n";

if ( -e "$vhostdir" ) {
    print "Look, dude. We already have a site in $vhostdir. Are you sure you haven't run this before?\n";
    exit 1;
}
if ( !-d $templatedir ) {
    print "Hey, the template directory ($templatedir) doesn't exist. We kind of need that.\n";
    exit 1;
}
if ( !-d $cachedir ) {
    mkdirAcl $cachedir, 600, 0, 0;
}

######################################################################
# Find the UID
######################################################################

print "Let's see what the UID we will use for $user is...\n";

my $uid = 2000; # Default value
my $skip = 0;
if(`id -u $user` =~ /^(\d+)$/){
    $uid = $1 + 0;
    $skip = 1;
} else {
    # Read in the /etc/passwd to determine the next biggest UID
    open(FILE, "/etc/passwd") || die("Could not read /etc/passwd");
    # Loop through our file and see if we have vhost users
    my $foundUid = 0;
    while(<FILE>) {
        if ( /^([^:]+):x:(\d+):\d+:[^:]*:\Q$basedir\// ) {
            if ( $2 > $foundUid ) {
                $foundUid = $2 + 0;
            }
        }
    }
    close(FILE);
    if ( $foundUid > 0 ) {
        $uid = $foundUid + 1;
    }
}
print "Ahha! Looks like the magic number is $uid\n";

######################################################################
# Create the base directory
######################################################################

mkdirAcl $basedir, 0755, 0, 0;

######################################################################
# Create the user and group
######################################################################

if(!$skip){
    print "Here comes the user ($user) and the home dir ($homedir)...\n";
    # Add the group and user account
    `groupadd -g $uid $user`;
    mkdirAcl $homedir, 0755, 0, 0;
        # homedir needs to be world-readable so www-data can serve files
        # homedir needs to be owned by root for chroot sftp to work
    `useradd -g $uid -G vhosted -u $uid -s /bin/false -M -d $homedir $user`;
    # Give the user a Diceware password
    my $secretFile = "$cachedir/secret-$user.txt";
    my $keyFile = "$cachedir/$user.key";
    open TMPFILE, '>', $secretFile and close TMPFILE or die "File error with password container: $!";
    chmod 0600, $secretFile;
    my $rand = int(rand(3)) + 4;  # random number from 4–6
    `xkcdpass -n $rand > $secretFile`;
    # Create a private/public key pair
    `ssh-keygen -q -t rsa -b 4096 -N '' -C $user -f "$keyFile"`;
    `openssl rsa -des3 -in "$keyFile" -out "$keyFile" -passout file:$secretFile`;
    chmod 0600, $keyFile, "$keyFile.pub";
    chown $uid, $uid, $keyFile, "$keyFile.pub";
    # Set up user's .ssh folder with public key
    mkdirAcl "$homedir/.ssh", 0700, $uid, $uid;
    move "$keyFile.pub", "$homedir/.ssh/id_rsa.pub";
    copy "$homedir/.ssh/id_rsa.pub", "$homedir/.ssh/authorized_keys";
}

######################################################################
# Create the folders beneath their home
######################################################################

print "I shall now construct the folders for the host ($vhost)\n";
$wwwGid = int(`id -g www-data`);
my @homeFolders = ("tmp", "logs");
foreach $folder (@homeFolders){
    mkdirAcl "$homedir/$folder", 0750, $uid, $wwwGid;
}
mkdirAcl $vhostdir, 0750, $uid, $wwwGid;
`chmod g+s $vhostdir`; # couldn't get perl to setgid right
    # setgid on vhostdir so sftp transfers keep group as www-data
my @folders = ("htdocs");
foreach $folder (@folders){
    mkdirAcl "$vhostdir/$folder", 0750, $uid, $wwwGid;
}

######################################################################
# Place templates where they need to go
######################################################################

print "Adding the configuration files...\n";

my $templatesDir = $o_templates;
my %replace = (
        '@VHOST@' => $vhost,
        '@VHOST@' => $vhostu,
        '@BASEDIR@' => $homedir,
        '@USER@' => $user,
        '@GROUP@' => $user,
        '@UID@' => $uid,
        '@GID@' => $uid
);
my %tpls = (
        "nginx" => "/etc/nginx/sites-available/$vhost",
	"php-fpm" => "/etc/php/7.0/fpm/pool.d/$user.conf"
);
foreach my $key (keys %tpls) {
    print "===============================================\n";
    print "$templatedir/$key\n";
    open(LOOPFILE, "$templatedir/$key") or die("Could not read template $templatedir/$key");
    undef $/;
    my $src = <LOOPFILE>;
    foreach my $holder (keys %replace) {
        $src =~ s/$holder/$replace{$holder}/g;
   }
   print "Writing $tpls{$key}...\n";
   open(LOOPFILEOUT, ">$tpls{$key}") or die("Could not write template $tpls{$key}");
   print LOOPFILEOUT $src;
   close(LOOPFILEOUT);
}

######################################################################
# Restart services
######################################################################

print "Restarting nginx and php-fpm...\n";
`service php7.0-fpm reload`;
`service nginx reload`;

print "\nIf you want SSL support on this domain, you should run...\n";
print "letsencrypt certonly --webroot -w $vhostdir -d $vhost -d www.$vhost\n";
print "...and then uncomment the relevant config sections\n\n";

######################################################################
# All done!
######################################################################

print "Everything is OK!\n";

__END__

=head1 NAME

vhost-boss - Create virtual hosts with ease.

=head1 SYNOPSIS

vhost-boss [options]

 Options:
   --help|-?               brief help message
   --man                   full documentation
   --host|-h               hostname of virtual site
   --user|-u               username for vhost
   --directory|-d          root directory for vhosts
   --cache|-c              directory for caching output
   --templates|-t          directory for templates

=head1 OPTIONS

=over 4

=item B<--help>

Print a brief help message and exits.

=item B<--man>

Prints the manual page and exits.

=item B<--host|-h>

Sets the host name for the virtual host. (e.g. example.com)

=item B<--user|-u>

Sets the name of the user account that will run the vhost.

=item B<--directory|-d>

Optional. Sets the root directory where vhosts will be created.
By default, this is set to /var/web.

=item B<--cache|-c>

Optional. Sets the cache directory where vhost private keys
will be written. By default, this is set to /var/lib/vhost-boss.

=item B<--templates|-t>

Optional. Sets the template directory, where templates are read.
By default, this is set to /usr/share/vhost-boss/templates.

=back

=head1 DESCRIPTION

B<vhost-boss> is intended to ease the creation of virtual hosts
on an Nginx/PHP-FPM setup. It reads templates, creates
directories, and initializes user accounts.

=cut
