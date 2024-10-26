requires 'Carp'     => '1.25';  # For trailing dot.
requires 'XSLoader' => '0.14';  # For XSLoader::load with no arguments.
requires 'perl'     => 'v5.12';

on build => sub {
    requires 'ExtUtils::ParseXS' => '3.12';   # For embedded typemaps.
};

on test => sub {
    requires 'Test2::Suite' => '0.000072';    # For Test2::V0.
};

on develop => sub {
    requires 'Devel::Cover::Report::Coveralls';
    requires 'Test::CPAN::Changes';
    requires 'Test::PerlTidy';
    requires 'Test::Pod';
    requires 'Test::Pod::Coverage';
};
