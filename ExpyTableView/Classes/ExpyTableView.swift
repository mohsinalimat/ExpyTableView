//
//  ExpyTableView.swift
//  Pods
//
//  Created by Okhan Okbay on 15/06/2017.

import UIKit

@objc public enum ExpyActionType: Int {
	case expand, collapse
}

@objc public protocol ExpyTableViewDataSource: UITableViewDataSource {
	@objc optional func canExpand(section: Int, inTableView tableView: ExpyTableView) -> Bool //default is true, which means all header cells are expandable
	func expandingCell(forSection section: Int, inTableView tableView: ExpyTableView) -> UITableViewCell
}

@objc public protocol ExpyTableViewDelegate: UITableViewDelegate {
	@objc optional func expyTableViewWillChangeState(withType type: ExpyActionType, forSection section: Int, inTableView tableView: ExpyTableView, animated: Bool)
	@objc optional func expyTableViewDidChangeState(withType type: ExpyActionType, forSection section: Int, inTableView tableView: ExpyTableView, animated: Bool)
}

public class ExpyTableView: UITableView {
	
	public weak var expyDataSource: ExpyTableViewDataSource?
	public weak var expyDelegate: ExpyTableViewDelegate?
	
	public fileprivate(set) var expandableSections: [Int: Bool] = [:]
	public fileprivate(set) var visibleSections: [Int: Bool] = [:]
	
	public var expandingAnimation: UITableViewRowAnimation = .fade
	public var collapsingAnimation: UITableViewRowAnimation = .fade
	
	override public init(frame: CGRect, style: UITableViewStyle) {
		super.init(frame: frame, style: style)
	}
	
	required public init?(coder aDecoder: NSCoder) {
		super.init(coder: aDecoder)
	}
	
	override public var dataSource: UITableViewDataSource? {
		get {
			return super.dataSource
		}
		set(dataSource) {
			expyDataSource = dataSource as? ExpyTableViewDataSource
			super.dataSource = self
		}
	}
	
	override public var delegate: UITableViewDelegate? {
		get {
			return super.delegate
		}
		set(delegate) {
			expyDelegate = delegate as? ExpyTableViewDelegate
			super.delegate = self
		}
	}
}

//MARK: Protocol Helper
extension ExpyTableView {
	fileprivate func verifyProtocolContainsSelector(_ aProtocol: Protocol, contains aSelector: Selector) -> Bool {
		return protocol_getMethodDescription(aProtocol, aSelector, true, true).name != nil || protocol_getMethodDescription(aProtocol, aSelector, false, true).name != nil
	}
	
	override public func responds(to aSelector: Selector!) -> Bool {
		if verifyProtocolContainsSelector(UITableViewDataSource.self, contains: aSelector) {
			return (super.responds(to: aSelector)) || (expyDataSource?.responds(to: aSelector) ?? false)
			
		}else if verifyProtocolContainsSelector(UITableViewDelegate.self, contains: aSelector) {
			return (super.responds(to: aSelector)) || (expyDelegate?.responds(to: aSelector) ?? false)
		}
		return super.responds(to: aSelector)
	}
	
	override public func forwardingTarget(for aSelector: Selector!) -> Any? {
		if verifyProtocolContainsSelector(UITableViewDataSource.self, contains: aSelector) {
			return expyDataSource
		}else if verifyProtocolContainsSelector(UITableViewDelegate.self, contains: aSelector) {
			return expyDelegate
		}
		return super.forwardingTarget(for: aSelector)
	}
}

extension ExpyTableView {
	fileprivate func expand(_ section: Int, inTableView tableView: ExpyTableView, animated: Bool) {
		animateTableView(withType: .expand, forSection: section, inTableView: tableView, animated: animated)
	}
	
	fileprivate func collapse(_ section: Int, inTableView tableView: ExpyTableView, animated: Bool) {
		animateTableView(withType: .collapse, forSection: section, inTableView: tableView, animated: animated)
	}
	
	private func animateTableView(withType type: ExpyActionType, forSection section: Int, inTableView tableView: ExpyTableView, animated: Bool) {
		
		guard let sectionIsExpandable = expandableSections[section], sectionIsExpandable else { return }
		
		if (type == .expand) && (visibleSections[section] == true) { return} //If section is visible and action type is expand, return.
		else if (type == .collapse) && (visibleSections[section] == false) { return } //If section is not visible and action type is collapse, return.
		
		//Inform the delegate here.
		expyDelegate?.expyTableViewWillChangeState?(withType: type, forSection: section, inTableView: tableView, animated: animated)
		
		visibleSections[section] = (type == .expand)
		
		if !animated {
			reloadDataAndResetExpansionStates(reset: false)
		}else {
			self.beginUpdates()
			
			//Don't insert or delete anything if section has only 1 cell.
			if let sectionRowCount = expyDataSource?.tableView(tableView, numberOfRowsInSection: section), sectionRowCount > 1 {
				
				var indexesToProcess: [IndexPath] = []
				
				//Start from 1, because 0 is the header cell.
				for row in 1..<sectionRowCount {
					indexesToProcess.append(IndexPath(row: row, section: section))
				}
				
				//Expand means inserting rows, collapse means deleting rows.
				if type == .expand {
					self.insertRows(at: indexesToProcess, with: expandingAnimation)
				}else if type == .collapse {
					self.deleteRows(at: indexesToProcess, with: collapsingAnimation)
				}
			}
			
			self.endUpdates()
		}
		
		let completionBlock = { [weak self] () -> (Void) in
			//Inform the delegate here.
			self?.expyDelegate?.expyTableViewDidChangeState?(withType: type, forSection: section, inTableView: tableView, animated: animated)
		}
		
		if animated{
			CATransaction.setCompletionBlock(completionBlock)
		}else {
			completionBlock()
		}
	}
}

extension ExpyTableView: UITableViewDataSource {
	public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		//If canExpandSections delegate method is not implemented, it defaults to true.
		let sectionIsExpandable = expyDataSource?.canExpand?(section: section, inTableView: self) ?? true
		let sectionIsVisible = visibleSections[section] ?? false
		let numberOfRows = expyDataSource?.tableView(self, numberOfRowsInSection: section) ?? 0
		
		guard sectionIsExpandable else {
			expandableSections[section] = false
			return numberOfRows
		}
		
		guard numberOfRows != 0 else {
			return 0
		}
		
		expandableSections[section] = true
		return sectionIsVisible ? numberOfRows : 1
	}
	
	public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let sectionIsExpandable = expandableSections[indexPath.section] ?? false
		
		guard sectionIsExpandable, indexPath.row == 0 else {
			return expyDataSource!.tableView(tableView, cellForRowAt: indexPath)
		}
		
		return expyDataSource!.expandingCell(forSection: indexPath.section, inTableView: self)
	}
}

extension ExpyTableView: UITableViewDelegate {
	
	public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		let sectionExistsInExpandableSections = expandableSections[indexPath.section] ?? false
		let sectionExistsInVisibleSections = visibleSections[indexPath.section] ?? false
		
		expyDelegate?.tableView?(tableView, didSelectRowAt: indexPath)
		
		guard sectionExistsInExpandableSections && (indexPath.row == 0) else { return }
		
		if sectionExistsInVisibleSections {
			collapse(indexPath.section, inTableView: self, animated: true)
		}else {
			expand(indexPath.section, inTableView: self, animated: true)
		}
	}
}

extension ExpyTableView {
	fileprivate func reloadDataAndResetExpansionStates(reset: Bool) {
		if reset { resetExpansionStates() }
		super.reloadData()
	}
	
	private func resetExpansionStates( ){
		expandableSections.removeAll()
		visibleSections.removeAll()
	}
}
