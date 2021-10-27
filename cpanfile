requires 'Carp'     => '1.25';  # For trailing dot.
requires 'XSLoader' => '0.14';  # For XSLoader::load with no arguments.

on test => sub {
    requires 'Test2::Suite' => '0.000072';    # For Test2::V0.
    requires 'version'      => '0.77';        # For version->parse.
};
