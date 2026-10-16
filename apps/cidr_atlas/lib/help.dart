// CIDR Atlas
// Offline contextual guidance and copyable fictional inventory examples.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum HelpTopic {
  gettingStarted,
  imports,
  ociDiscovery,
  planning,
  cidrBasics,
  routingDomains,
  cli,
}

Future<void> showAtlasHelp(
  BuildContext context, {
  HelpTopic topic = HelpTopic.gettingStarted,
}) async {
  await showDialog<void>(
    context: context,
    builder: (_) => AtlasHelpDialog(initialTopic: topic),
  );
}

class AtlasHelpDialog extends StatefulWidget {
  const AtlasHelpDialog({
    super.key,
    this.initialTopic = HelpTopic.gettingStarted,
  });

  final HelpTopic initialTopic;

  @override
  State<AtlasHelpDialog> createState() => _AtlasHelpDialogState();
}

class _AtlasHelpDialogState extends State<AtlasHelpDialog> {
  late HelpTopic _topic;
  final _scroll = ScrollController();
  String? _copied;

  static const _labels = {
    HelpTopic.gettingStarted: 'Getting started',
    HelpTopic.imports: 'CSV and JSON imports',
    HelpTopic.ociDiscovery: 'OCI discovery',
    HelpTopic.planning: 'Planning a range',
    HelpTopic.cidrBasics: 'CIDR and capacity',
    HelpTopic.routingDomains: 'Routing domains',
    HelpTopic.cli: 'CLI examples',
  };

  static const _titles = {
    HelpTopic.gettingStarted: 'Where do I enter a prefix?',
    HelpTopic.imports: 'Import files',
    HelpTopic.ociDiscovery: 'Discover existing OCI CIDRs',
    HelpTopic.planning: 'Plan a new range',
    HelpTopic.cidrBasics: 'Read CIDRs and capacity',
    HelpTopic.routingDomains: 'Choose an overlap-check scope',
    HelpTopic.cli: 'Use the desktop CLI',
  };

  @override
  void initState() {
    super.initState();
    _topic = widget.initialTopic;
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _select(HelpTopic topic) {
    if (_topic == topic) return;
    setState(() {
      _topic = topic;
      _copied = null;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Widget _paragraph(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: SelectableText(text, style: const TextStyle(height: 1.5)),
  );

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(top: 4, bottom: 8),
    child: Text(
      text,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    ),
  );

  Widget _example(String label, String value) => Container(
    margin: const EdgeInsets.only(bottom: 18),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (_copied == label)
              Semantics(liveRegion: true, child: const Text('Copied')),
            IconButton(
              tooltip: 'Copy $label',
              icon: const Icon(Icons.copy_outlined, size: 18),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: value));
                if (mounted) setState(() => _copied = label);
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        SelectableText(
          value,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            height: 1.5,
          ),
        ),
      ],
    ),
  );

  Widget _reference(String label, String path) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12)),
        SelectableText(
          'https://docs.oracle.com/en-us/iaas/$path',
          style: TextStyle(
            fontSize: 12,
            height: 1.5,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ],
    ),
  );

  List<Widget> _content() => switch (_topic) {
    HelpTopic.gettingStarted => [
      _paragraph(
        'OCI discovery reads existing CIDRs automatically. You choose the profile, '
        'region, compartment, and routing domain; you do not enter a prefix for '
        'discovery. “0 network CIDRs” is the number returned for that scope.',
      ),
      _heading('Choose the workflow'),
      _paragraph(
        'Import → Discover from OCI CLI: read existing VCN and subnet CIDRs.\n\n'
        'New prefix: register a known or planned network. Enter a full CIDR, '
        'such as 10.64.0.0/20, its name, and routing domain.\n\n'
        'Check CIDR: test a full CIDR against local inventory without saving.\n\n'
        'Planner: choose a containing pool, then enter a requested child prefix '
        'length such as 24, or size a subnet from address demand.\n\n'
        'Import → Choose CSV or JSON: preview an offline inventory file.',
      ),
      _heading('Start with your address plan'),
      _paragraph(
        'New installations start empty. Add a parent allocation such as '
        '10.64.0.0/16, reserve a VCN under it, and add or import subnets. Select '
        'parents explicitly. All examples in this guide are fictional; use '
        'fictional-isolated to keep practice records separate.',
      ),
      _paragraph(
        'Inventory and reservations stay in local SQLite. A local reservation '
        'does not create an OCI resource. Export JSON after important changes; '
        'transfer exports instead of sharing a live SQLite database.',
      ),
      _paragraph(
        'To start over, use Clear inventory (the delete icon above the '
        'inventory table): delete every record or one routing domain after '
        'typing CLEAR. Export a backup first if needed. Change history is '
        'kept and OCI is not touched.',
      ),
    ],
    HelpTopic.imports => [
      _paragraph(
        'Choose CSV or JSON, inspect the preview, then select Apply import. '
        'Offline files need no OCI connection. CIDRs come from the file; '
        'Import does not ask you to type a new prefix.',
      ),
      _heading('CSV'),
      _paragraph(
        'Use the documented column names shown in the example. '
        'cidr, name, and routingDomain are required. '
        'Use stable id values and matching parentId values for an explicit '
        'allocation → VCN → subnet hierarchy.',
      ),
      _example(
        'CSV example',
        'id,cidr,name,routingDomain,kind,status\n'
            'example-pool,10.64.0.0/16,Fictional allocation,fictional-isolated,allocation,reserved\n',
      ),
      _heading('JSON'),
      _paragraph(
        'Use an exported CIDR Atlas JSON backup as a template. CSV and Atlas '
        'backups retain their own routing domains. OCI JSON uses the '
        '“Routing domain for OCI imports” field and can contain VCN/subnet '
        'arrays or supported CLI-style resource data.',
      ),
      _example(
        'JSON backup example',
        '{\n'
            '  "format": "cidr-atlas",\n'
            '  "version": 1,\n'
            '  "records": [{\n'
            '    "id": "example-pool",\n'
            '    "cidr": "10.64.0.0/16",\n'
            '    "name": "Fictional allocation",\n'
            '    "routingDomain": "fictional-isolated",\n'
            '    "kind": "allocation",\n'
            '    "status": "reserved"\n'
            '  }]\n'
            '}',
      ),
      _heading('Preview and apply'),
      _paragraph(
        'Invalid CIDRs, missing required fields, and invalid hierarchy block '
        'Apply. A valid import saves the merged batch atomically. Discovered '
        'routing conflicts remain visible for review. OCI refresh retains '
        'local owner, notes, status, parent, environment, and customer fields. '
        'Omitted records are never automatically deleted or retired.',
      ),
    ],
    HelpTopic.ociDiscovery => [
      _paragraph(
        'Discovery reads the existing VCN and subnet CIDRs for your scope. '
        'There is no CIDR or requested prefix length to enter.',
      ),
      _heading('Profile, authentication, and scope'),
      _paragraph(
        '1. Choose an existing OCI CLI profile and confirm its tenancy and '
        'default region. Select API key or Security token authentication to '
        'match that profile.\n\n'
        '2. Select Load scopes. Choose a READY region, optionally add other '
        'READY regions, or select All READY subscribed regions. Choose one '
        'direct compartment, or use the all-compartments option below. '
        'Enter scope manually accepts comma-separated region names when '
        'selectors cannot be loaded; resource IAM permissions still apply.\n\n'
        '3. Enter a routing domain, then select Discover inventory. Review '
        'the preview before Apply import saves the valid batch locally.',
      ),
      _paragraph(
        'All accessible compartments and subcompartments includes tenancy root '
        'and all visible active descendants. A selected compartment reads only '
        'its direct resources. The region and compartment choices are independent: '
        'one region/all compartments, multiple regions/one compartment, or both '
        'broad options are supported. All pages from every chosen pair return '
        'to one combined preview and one atomic local apply. A referenced VCN '
        'can be included as context without collecting its other subnets.',
      ),
      _heading('Example scopes'),
      _paragraph(
        'One environment: choose eu-frankfurt-1 and a development compartment.\n\n'
        'Regional inventory: choose eu-frankfurt-1 and enable all compartments.\n\n'
        'Shared application: choose us-phoenix-1, add eu-frankfurt-1, and select '
        'its compartment.\n\n'
        'Broad inventory: enable both all-region and all-compartment options. '
        'READY subscriptions and accessible compartments are freshly enumerated '
        'during discovery, then each region/compartment pair is read.',
      ),
      _heading('Permissions and coverage'),
      _paragraph(
        'Accessible compartment enumeration requires IAM visibility and does '
        'not grant permission to list VCNs or subnets. IAM-hidden compartments '
        'may remain unseen. A failed required enumeration or network-list '
        'request returns no applicable partial result. Read the reported '
        'scope, collection interval, and warnings before treating gaps as '
        'candidates for allocation.',
      ),
      _heading('If discovery finds no networks (0 network CIDRs)'),
      _paragraph(
        'There is nothing to apply. Check the profile/tenancy, resource regions, '
        'scope mode, and IAM permissions. With a selected direct compartment, '
        'networks may instead be in a child: select that child or enable all '
        'compartments. If all compartments are already included, review '
        'permissions and region subscriptions. Entering a new range belongs '
        'in New prefix or Planner.',
      ),
      _paragraph(
        'After an empty result from one direct compartment, Retry with all '
        'accessible compartments starts discovery again at once with the same '
        'profile, authentication, regions, and routing domain, including '
        'subcompartments. Tenancy root usually holds no networks itself.',
      ),
      _heading('If a request fails'),
      _paragraph(
        'Repair the selected CLI credentials or renew an expired session '
        'outside CIDR Atlas, then retry. For permission or scope errors, '
        'confirm the compartment and ask your tenancy administrator to '
        'check access. A failed required request cannot apply partial results.',
      ),
      _paragraph(
        'CLI and configuration paths accepts optional executable/configuration '
        'paths. Opening discovery reads profile-selection metadata; network '
        'requests begin with Load scopes or Discover inventory. While they run, '
        'a progress panel centered over the dialog shows the current step, '
        'completed region/compartment scopes when known, elapsed time, and the '
        'collection limit; its Cancel stops the request and returns to the '
        'form. The dialog Cancel closes discovery and discards the result. '
        'Coverage describes a scoped observation, not a complete '
        'tenancy audit; omitted ranges are not evidence of free space.',
      ),
      _heading('Official Oracle references — select or copy a URL'),
      _reference(
        'Configuration and profiles',
        'Content/API/Concepts/sdkconfig.htm',
      ),
      _reference(
        'Session-token authentication',
        'Content/API/SDKDocs/clitoken.htm',
      ),
      _reference(
        'VCN list scope and pagination',
        'tools/oci-cli/latest/oci_cli_docs/cmdref/network/vcn/list.html',
      ),
      _reference(
        'Subnet list scope and pagination',
        'tools/oci-cli/latest/oci_cli_docs/cmdref/network/subnet/list.html',
      ),
      _reference(
        'Compartment hierarchy and accessible scopes',
        'tools/oci-cli/latest/oci_cli_docs/cmdref/iam/compartment/list.html',
      ),
      _reference(
        'Subscribed regions',
        'tools/oci-cli/latest/oci_cli_docs/cmdref/iam/region-subscription/list.html',
      ),
      _reference(
        'IAM permissions',
        'Content/Identity/Reference/corepolicyreference.htm',
      ),
    ],
    HelpTopic.planning => [
      _paragraph(
        'Choose a routing domain and an allocation or VCN pool. A manual '
        'pool is a full containing CIDR, such as 10.64.0.0/16. It defines '
        'where to search; it is not the new reservation. Choose a VCN pool '
        'to plan a subnet, or an allocation to plan a VCN.',
      ),
      _heading('Choose by prefix'),
      _paragraph(
        'Enter only the child prefix number in Requested prefix length, '
        'for example 24. A /16 contains 256 aligned /24 slots before '
        'inventory blockers. Select Find available space to calculate '
        'candidates and exact free-slot totals.',
      ),
      _heading('Size from address demand'),
      _paragraph(
        'Select Subnet and OCI IPv4 subnet. Enter current or already-planned '
        'peak IP demand, an explicit growth percentage (including 0), and '
        'additional service / HA / DR IPs. Growth is applied once to that '
        'basis. Additional IPs must exclude demand already counted.',
      ),
      _example(
        'Demand example',
        '100 IPs × 1.20 + 4 additional IPs = 124 required\n'
            'OCI /25: 128 total − 3 reserved = 125 assignable\n'
            '1 spare after the stated allowances\n'
            'OCI /26: 64 total − 3 reserved = 61; does not fit',
      ),
      _paragraph(
        'CIDR Atlas’s OCI IPv4 subnet policy supports /16–/30. Generic '
        'capacity shows mathematical totals; it does not claim provider '
        'assignable capacity. Plan VCN sizes from their child requirements.',
      ),
      _heading('Review and reserve'),
      _paragraph(
        'Select a candidate, review its rationale, then select Reserve to '
        'review and save a local record. Saving rechecks the current inventory. '
        'Input or inventory changes clear previous recommendations. This '
        'does not provision an OCI network. Availability depends on inventory '
        'coverage and the chosen routing domain.',
      ),
      _reference(
        'Oracle address reservations',
        'Content/Network/Concepts/overview.htm',
      ),
    ],
    HelpTopic.cidrBasics => [
      _paragraph(
        'A CIDR combines a network address and network-bit count: '
        '10.64.1.0/24. A larger prefix number means a smaller range. '
        'IPv4 /24 has 256 total addresses; /25 has 128.',
      ),
      _heading('Use the network boundary'),
      _paragraph(
        'Enter 10.64.1.0/24, not 10.64.1.3/24. CIDR Atlas rejects nonzero '
        'host bits instead of silently changing your requested range. '
        'The inspector shows the network, mask, exact range, and total.',
      ),
      _heading('Total and provider capacity'),
      _paragraph(
        'An OCI IPv4 subnet reserves its first two and final addresses: '
        'a /24 has 256 total and 253 assignable addresses. Generic policy '
        'reports exact totals without assuming a provider’s usable capacity. '
        'Generic /31 and /32 calculations remain valid mathematical prefixes. '
        'IPv6 uses exact totals; the app does not claim an OCI IPv6 '
        'assignable count.',
      ),
      _heading('Addresses and aligned slots'),
      _paragraph(
        'One recorded /25 inside a /24 leaves 128 free addresses but no '
        'complete free /24 slot. Inspector’s “Aligned child slots before '
        'blockers” is theoretical subdivision; Planner’s free slots include '
        'the inventory blockers. A calculated containing supernet does '
        'not authorize using that larger range.',
      ),
      _paragraph(
        'Active, planned, and reserved ranges block allocation in their '
        'domain. Retired ranges do not. Always review coverage and '
        'unimported connected networks before treating space as available.',
      ),
      _reference(
        'Oracle CIDRs and reserved addresses',
        'Content/Network/Concepts/overview.htm',
      ),
    ],
    HelpTopic.routingDomains => [
      _paragraph(
        'A routing domain is a local overlap-check scope chosen by you. '
        'Use a consistent name for address plans that must coexist. '
        'Tenancy and region alone do not define this scope.',
      ),
      _heading('Fictional examples'),
      _paragraph(
        'corporate-connected: OCI VCNs and on-premises ranges intended '
        'to communicate through DRG, VPN, or FastConnect. Include the '
        'connected address plans in the same domain.\n\n'
        'customer-a-isolated and customer-b-isolated: independent labs '
        'that remain isolated may intentionally reuse the same CIDR.',
      ),
      _heading('Parents and connectivity'),
      _paragraph(
        'Choose explicit allocation → VCN → subnet parents. Numerical '
        'containment alone does not establish an approved relationship. '
        'Matching OCI resource IDs can establish VCN/subnet membership. '
        'Multiple CIDRs on a resource remain separate prefix records.',
      ),
      _paragraph(
        'The hierarchy shows address ancestry and known OCI membership. '
        'It does not discover routes, DRGs, firewall rules, or real-world '
        'reachability. “Available” means available in the supplied local '
        'inventory and routing domain, subject to its coverage.',
      ),
      _reference(
        'Oracle connected-network constraints',
        'Content/Network/Concepts/overview.htm',
      ),
    ],
    HelpTopic.cli => [
      _paragraph(
        'The desktop CLI uses the same domain and SQLite rules as the app. '
        'These fictional examples use a separate database. Replace the '
        'file paths and scope values for your work. The compiled executable '
        'is cidrctl; source users can use scripts/cidrctl.',
      ),
      _heading('Preview an offline import'),
      _example(
        'CLI import preview',
        'cidrctl --db fictional.sqlite import csv --file fictional.csv',
      ),
      _paragraph(
        'Add --apply only after reviewing the preview. An import writes '
        'the valid batch atomically. Omitted records are retained.',
      ),
      _example(
        'CLI import apply',
        'cidrctl --db fictional.sqlite import csv --file fictional.csv --apply',
      ),
      _heading('Preview a recommendation'),
      _example(
        'CLI planning preview',
        'cidrctl --db fictional.sqlite recommend \\\n'
            '  --pool 10.64.0.0/16 --routing-domain fictional-isolated \\\n'
            '  --prefix 24 --kind subnet --policy oci_ipv4',
      ),
      _paragraph(
        'Use exactly one of --prefix or --addresses. Demand also requires '
        '--growth-percent; --additional defaults to 0. Add --apply and '
        '--name to reserve the first candidate locally. Preview changes no '
        'inventory or history records, although opening a new database path '
        'can create its file.',
      ),
      _heading('Discover existing OCI networks'),
      _example(
        'CLI OCI preview',
        'cidrctl --db fictional.sqlite discover oci \\\n'
            '  --profile FICTIONAL --region us-phoenix-1 \\\n'
            '  --compartment-id ocid1.compartment.oc1..fictional \\\n'
            '  --routing-domain fictional-isolated',
      ),
      _paragraph(
        'Discovery is an explicit OCI read and previews by default. '
        'Use --auth security_token for a session profile. --region accepts '
        'repeated options or comma-separated names. Replace --region with '
        '--all-regions for every READY subscription. Replace --compartment-id '
        'with --all-compartments to include root and accessible active '
        'descendants. The two broad options can be used independently. '
        'Required enumeration/list failures cannot apply partial inventory. '
        'Use cidrctl discover oci --help for scope examples.',
      ),
      _example(
        'CLI all-scope OCI preview',
        'cidrctl --db fictional.sqlite discover oci --profile FICTIONAL '
            '--all-regions --all-compartments '
            '--routing-domain fictional-connected',
      ),
    ],
  };

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return AlertDialog(
      semanticLabel: 'CIDR Atlas help and examples',
      title: const Text('Help and examples'),
      insetPadding: const EdgeInsets.all(24),
      constraints: const BoxConstraints(maxWidth: 1000),
      content: SizedBox(
        width: 900,
        height: (size.height - 220).clamp(220, 620),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final guide = Scrollbar(
              controller: _scroll,
              child: SingleChildScrollView(
                key: const ValueKey('help-content-scroll'),
                controller: _scroll,
                padding: const EdgeInsets.only(right: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _titles[_topic]!,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    ..._content(),
                  ],
                ),
              ),
            );
            if (constraints.maxWidth < 700) {
              return Column(
                children: [
                  DropdownButtonFormField<HelpTopic>(
                    key: const ValueKey('help-topic-selector'),
                    initialValue: _topic,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Help topic'),
                    items: [
                      for (final topic in HelpTopic.values)
                        DropdownMenuItem(
                          value: topic,
                          child: Text(_labels[topic]!),
                        ),
                    ],
                    onChanged: (topic) {
                      if (topic != null) _select(topic);
                    },
                  ),
                  const SizedBox(height: 20),
                  Expanded(child: guide),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 210,
                  child: ListView(
                    children: [
                      for (final topic in HelpTopic.values)
                        ListTile(
                          key: ValueKey('help-topic-${topic.name}'),
                          selected: topic == _topic,
                          title: Text(_labels[topic]!),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          onTap: () => _select(topic),
                        ),
                    ],
                  ),
                ),
                const VerticalDivider(width: 32),
                Expanded(child: guide),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close help'),
        ),
      ],
    );
  }
}
