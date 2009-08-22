
use strict;
use warnings;

use ExtUtils::MakeMaker;

WriteMakefile(
  DISTNAME  => 'POEx-ProxySession',
  NAME      => 'POEx::ProxySession',
  AUTHOR    => 'Nicholas\ Perez\ \<nperez\@cpan\.org\>',
  ABSTRACT  => 'Simple\,\ IKC\-like\ remote\ session\ proxifier',
  VERSION   => '0.092340',
  EXE_FILES => [ qw() ],
  (eval { ExtUtils::MakeMaker->VERSION(6.31) } ? (LICENSE => 'gpl') : ()),
  PREREQ_PM    => {
    "POEx::Role::TCPClient" => '0.092340',
    "POEx::Role::TCPServer" => '0.092340',
  },
);
