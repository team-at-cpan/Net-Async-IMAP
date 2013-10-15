#!/usr/bin/env perl
use strict;
use warnings;
use Closure::Explicit qw(callback);
use Tickit::DSL qw(:async);

vbox {
	menubar {
		submenu File => callback {
			# not yet implemented...
			menuitem Open  => callback { warn 'open'};
			menuspacer;
			menuitem Exit  => callback { tickit->stop };
		};
		# we'll populate this later
		submenu Account => callback {
			menuitem 'Add new account' => callback { };
			menuspacer;
			menuitem 'First account' => callback { };
		};
		menuspacer;
		submenu Help => callback {
			menuitem About => callback { warn 'about' };
		};
	};

	statusbar { };
};
tickit->run;

