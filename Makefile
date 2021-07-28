PREFIX ?= /usr/local
EXEC_PREFIX ?= $(PREFIX)
SYSCONFDIR ?= /etc
BINDIR ?= $(EXEC_PREFIX)/bin

MCE_SITESPECT_ROOT          ?= /opt/sitespect
MCE_SITESPECT_UTIL          ?= $(MCE_SITESPECT_ROOT)/lib/perl/SiteSpect/Util
MCE_SITESPECT_BINDIR        ?= $(MCE_SITESPECT_ROOT)/bin
MCE_BINDIR                  ?= $(BINDIR)
MCE_USER                    ?= sitespect
MCE_EMAILTO                 ?= $(MCE_USER)
MCE_SERVERGROUP             ?= 1
MCE_AUTO_SCALING_GROUP_NAME ?= stg-sitespect-engine-ec2
MCE_ONLINE_ENGINE_LOG       ?= /tmp/online_engine.log
MCE_OFFLINE_ENGINE_LOG      ?= /tmp/offline_engine.log

DESTDIR ?=
PKGDIR  ?= $(dir $(realpath $(firstword $(MAKEFILE_LIST))))/pkg

CRON    := $(DESTDIR)/$(SYSCONFDIR)/cron.d/manage_cluster_engines
MCE     := $(DESTDIR)/$(BINDIR)/mce
PKG     := $(PKGDIR)/mce.tar.gz

ENVSUBST ?= envsubst
INSTALL  ?= install
MKDIR    ?= mkdir
RM       ?= rm
TAR      ?= tar

.PHONY: default bin cron pkg

default: pkg

# This target depends on this Makefile itself, as the command to construct the
# cron file is defined inline.
$(CRON): templates/cron.tmpl $(firstword $(MAKEFILE_LIST))
	$(MKDIR) -p $(dir $@)
	MCE_SITESPECT_UTIL=$(MCE_SITESPECT_UTIL) \
		MCE_SITESPECT_BINDIR=$(MCE_SITESPECT_BINDIR) \
		MCE_BINDIR=$(MCE_BINDIR) \
		MCE_USER=$(MCE_USER) \
		MCE_EMAILTO=$(MCE_EMAILTO) \
		MCE_SERVERGROUP=$(MCE_SERVERGROUP) \
		MCE_AUTO_SCALING_GROUP_NAME=$(MCE_AUTO_SCALING_GROUP_NAME) \
		MCE_ONLINE_ENGINE_LOG=$(MCE_ONLINE_ENGINE_LOG) \
		MCE_OFFLINE_ENGINE_LOG=$(MCE_OFFLINE_ENGINE_LOG) \
		$(ENVSUBST) < $< > $@

$(MCE): scripts/mce
	$(INSTALL) -Dm0755 $< $@

$(PKG): $(MCE) $(CRON)
	$(MKDIR) -p $(dir $@)
	$(RM) -f $@
	cd $(DESTDIR) && $(TAR) --numeric-owner --owner=0 --group=0 -cvf $@ *

bin: $(MCE)

cron: $(CRON)

pkg: $(PKG)
