requires 'XSLoader';

on test => sub {
    requires 'Test2::Suite' => '0.000072';    # For Test2::V0.
    requires 'version'      => '0.77';        # For version->parse.
};
