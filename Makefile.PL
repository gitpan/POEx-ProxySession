
use strict;
use warnings;



use ExtUtils::MakeMaker 6.31;



my %WriteMakefileArgs = (
  'ABSTRACT' => 'Simple, IKC-like remote session proxifier',
  'AUTHOR' => 'Nicholas Perez <nperez@cpan.org>',
  'BUILD_REQUIRES' => {
    'POE' => '0',
    'Test::More' => '0'
  },
  'CONFIGURE_REQUIRES' => {
    'ExtUtils::MakeMaker' => '6.31'
  },
  'DISTNAME' => 'POEx-ProxySession',
  'EXE_FILES' => [],
  'LICENSE' => 'perl',
  'NAME' => 'POEx::ProxySession',
  'PREREQ_PM' => {
    'Class::MOP' => '0',
    'Moose::Util' => '0',
    'MooseX::Declare' => '0',
    'MooseX::Types' => '0',
    'MooseX::Types::Moose' => '0',
    'MooseX::Types::Structured' => '0',
    'POE::Filter::Reference' => '0',
    'POEx::Role::SessionInstantiation' => '0',
    'POEx::Role::TCPClient' => '0',
    'POEx::Role::TCPServer' => '0',
    'POEx::Types' => '0',
    'Socket' => '0',
    'Storable' => '0',
    'aliased' => '0'
  },
  'VERSION' => '1.102760',
  'test' => {
    'TESTS' => 't/*.t'
  }
);


unless ( eval { ExtUtils::MakeMaker->VERSION(6.56) } ) {
  my $br = delete $WriteMakefileArgs{BUILD_REQUIRES};
  my $pp = $WriteMakefileArgs{PREREQ_PM};
  for my $mod ( keys %$br ) {
    if ( exists $pp->{$mod} ) {
      $pp->{$mod} = $br->{$mod} if $br->{$mod} > $pp->{$mod};
    }
    else {
      $pp->{$mod} = $br->{$mod};
    }
  }
}

delete $WriteMakefileArgs{CONFIGURE_REQUIRES}
  unless eval { ExtUtils::MakeMaker->VERSION(6.52) };

WriteMakefile(%WriteMakefileArgs);



