use ConfigCommon;
use ConfigFSM;
use CiscoTypes;
@ISA = ('Exporter');
@EXPORT = (qw ($START));
use vars (qw (@ISA @EXPORT $fsm));

select (STDOUT); $|=1;
1;
