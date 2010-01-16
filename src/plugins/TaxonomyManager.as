package plugins {
	
	import com.graphmind.data.NodeItemData;
	import com.graphmind.display.NodeItem;
	import com.graphmind.net.RPCServiceHelper;
	import com.graphmind.net.SiteConnection;
	
	import flash.events.ContextMenuEvent;
	
	import mx.controls.Alert;
	import mx.rpc.events.ResultEvent;
	
	public class TaxonomyManager {
		
		public static const TAXONOMY_MANAGER_NODE_VOCABULARY_TYPE:String = 'vocabulary';
		// @TODO add color
//		public static const TAXONOMY_MANAGER_NODE_VOCABULARY_COLOR:uint = 0xFF0000;
		
		/**
		 * Implementation of hook_node_context_menu_alter().
		 */
		public static function hook_node_context_menu(params:Object = null):void {
			(params.data as Array).push({title: 'Load taxonomy', event: TaxonomyManager.loadFullTaxonomyTree, separator: true});
		}
		
		/**
		 * Callback for loading and attaching taxonomy tree.
		 */
		public static function loadFullTaxonomyTree(event:ContextMenuEvent):void {
			var node:NodeItem = NodeItem.getLastSelectedNode();
			var baseSiteConnection:SiteConnection = SiteConnection.getBaseSiteConnection();
			
			// @FIXME it's not sure it exists at all!!!
			node.selectNode();
			
			RPCServiceHelper.createRPC(
				'taxonomy',
				'getAll',
				'amfphp',
				baseSiteConnection.url,
				function(_event:ResultEvent):void {
					onTaxonomyRequestReady(_event, baseSiteConnection, node);
				}
			).send(baseSiteConnection.sessionID);
		}
		
		private static function onTaxonomyRequestReady(event:ResultEvent, sc:SiteConnection, baseNode:NodeItem):void {
			for each (var vocabulary:Object in event.result) {
				vocabulary.plugin = 'TaxonomyManager';
				var vocabularyNodeItemData:NodeItemData = new NodeItemData(
					vocabulary,
					NodeItemData.NORMAL, // @TODO make it as a VOCABULARY
					sc
				);
				vocabularyNodeItemData.title = vocabulary.name;
				vocabularyNodeItemData.type = TAXONOMY_MANAGER_NODE_VOCABULARY_TYPE;
				var vocabularyNode:NodeItem = new NodeItem(vocabularyNodeItemData);
				baseNode.addChildNode(vocabularyNode);
				
				var term_hierarchy:Object = {};
				var term_storage:Object = {0: vocabularyNode};
				for each (var term:Object in vocabulary.terms) {
					term.plugin = 'TaxonomyManager';
					var termNodeItemData:NodeItemData = new NodeItemData(
						term,
						NodeItemData.TERM,
						sc
					);
					termNodeItemData.title = term.name;
					var termNodeItem:NodeItem = new NodeItem(termNodeItemData);
					var parentID:String = term.parents[0] || 'none';
					if (!term_hierarchy.hasOwnProperty(parentID)) {
						term_hierarchy[parentID] = [];
					}
					(term_hierarchy[parentID] as Array).push(termNodeItem);
					term_storage[term.tid] = termNodeItem;
				}
				
				for (var _parentID:* in term_hierarchy) {
					for each (var termNode:NodeItem in term_hierarchy[_parentID]) {
						(term_storage[_parentID] as NodeItem).addChildNode(termNode);
					}
				}
			}
		}
		
		/**
		 * Implementation of hook_node_moved.
		 */
		public static function hook_node_moved(data:Object):void {
			// @TODO revert plan if action cannot be done
			var node:NodeItem = data.node as NodeItem;
			var baseConnection:SiteConnection = SiteConnection.getBaseSiteConnection();
			
			// Node is not part of the plugin.
			if (!_isTaxonomyPluginNode(node, NodeItemData.TERM)) return;
			
			var parentNode:NodeItem = node.getParentNode();
			
			// Deleting term
			if (!_isTaxonomyPluginNode(parentNode)) {
				_removePluginInfoFromNode(node)
				hook_node_delete({node: node});
				return;
			}

			var order:Array = [];
			for each (var child:NodeItem in parentNode.getChildNodes) {
				if (child.getNodeData().hasOwnProperty('tid')) {
					order.push(child.getNodeData().tid);
				}
			}
			
			var childNodes:Array = _changeChildsVocabulary(node, parentNode.getNodeData().vid || 0);
			_changeSiblingsWeight(node);
			
			RPCServiceHelper.createRPC(
				'graphmindTaxonomyManager',
				'moveTerm',
				'amfphp',
				baseConnection.url,
				function(_event:ResultEvent):void{Alert.show('Great success');}
			).send(
				baseConnection.sessionID,
				node.getNodeData().tid,
				parentNode.getNodeData().vid || 0,
				parentNode.getNodeData().tid || 0,
				order.join('|'),
				childNodes.join('|')
			);
		}

		/**
		 * Check if the node created by the TaxonomyManager plugin and has a certain type.
		 */
		private static function _isTaxonomyPluginNode(node:NodeItem, type:String = null):Boolean {
			if (!node.getNodeData().hasOwnProperty('plugin') || !node.getNodeData().plugin == 'TaxonomyManager') {
				return false;
			}
			return type == null ? true : node.nodeItemData.type == type;
		}
		
		/**
		 * Change the subtree's VID to a given value.
		 * If a node moved to another vocabulary, all subterms should be adopted.
		 * 
		 * @param NodeItem node
		 * @param integer vid
		 */
		private static function _changeChildsVocabulary(node:NodeItem, vid:int):Array {
			node.getNodeData().vid = vid;
			
			var nodes:Array = [node.getNodeData().tid || 0];
			for each (var child:NodeItem in node.getChildNodes) {
				nodes = nodes.concat(_changeChildsVocabulary(child, vid));
			}
			
			return nodes;
		}
		
		/**
		 * Recount weight values of a term's siblings
		 * 
		 * @param NodeItem node
		 */
		private static function _changeSiblingsWeight(node:NodeItem):void {
			var parentNode:NodeItem = node.getParentNode();
			var weight:int = 0;
			for each (var child:NodeItem in parentNode.getChildNodes) {
				child.getNodeData().weight = weight++;
			}
		}
		
		/**
		 * Implementation of hook_node_delete().
		 * 
		 * @param Object data
		 */
		public static function hook_node_delete(data:Object):void {
			var node:NodeItem = data.node as NodeItem;
			var baseSiteConnection:SiteConnection = SiteConnection.getBaseSiteConnection();
			
			if (!_isTaxonomyPluginNode(node, NodeItemData.TERM)) return;
			
			RPCServiceHelper.createRPC(
				'graphmindTaxonomyManager',
				'deleteTerm',
				'amfphp',
				baseSiteConnection.url,
				_onTermDeleted
			).send(baseSiteConnection.sessionID, node.getNodeData().tid || 0);
		}
		
		/**
		 * Callback for delete node service call.
		 */
		private static function _onTermDeleted(event:ResultEvent):void {
			// Term is deleted with all subterms
		}
		
		/**
		 * De-pluginize a subtree.
		 */
		private static function _removePluginInfoFromNode(node:NodeItem):void {
			node.getNodeData().plugin = undefined;
			
			for each (var child:NodeItem in node.getChildNodes) {
				_removePluginInfoFromNode(child);
			}
		}
		
		/**
		 * Implementation of hook_node_created().
		 * 
		 * @param Object data
		 */
		public static function hook_node_created(data:Object):void {
			var baseSiteConnection:SiteConnection = SiteConnection.getBaseSiteConnection();
			
			var parent:NodeItem = data.node as NodeItem;
			if (!_isTaxonomyPluginNode(parent)) return;
			
			RPCServiceHelper.createRPC(
				'graphmindTaxonomyManager',
				'addSubtree',
				'amfphp',
				baseSiteConnection.url,
				_onSubtreeAdded
			).send(baseSiteConnection.sessionID, 333, 444, [1, 2, [3, 4, 5, [6], 7, [8, 9, 10], 11]]);
		}
		
		private static function _onSubtreeAdded(event:ResultEvent):void {
			
		}
	}
	
}
