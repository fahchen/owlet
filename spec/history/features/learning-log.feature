# English: learning-log.feature · 简体中文: learning-log.zh-CN.feature
Feature: History as the learning log
  Reviewing history, the user can see what was translated that day, where it was met, and which words were saved from it.

  Rule: History records the app the source text came from
    Scenario: A translation triggered by selecting text
      Given the user selects text in a mail app and triggers a translation
      When the result is generated successfully
      Then the history record's source app is the mail app

    Scenario: A translation of manually entered text
      Given the user types text in the main window and translates it
      When the result is generated successfully
      Then the history record has no source app

  Rule: The history list is grouped by day, newest first
    Scenario: Records across days
      Given the user has 3 records today and 5 yesterday
      When the user opens history
      Then the records are split into two groups, with today's group first

  Rule: History can be filtered by "has saved entries" and by source app, combined with the Translate / Polish filter
    Scenario: Show only polishes that produced saved entries
      Given the user has several translate and polish records, some of which had expressions saved
      When the user chooses Polish and checks "Has saved entries"
      Then only polish records with saved expressions are shown

    Scenario: Show only records from one app
      Given the user has records from a mail app and from Slack
      When the user sets the source app to Slack
      Then only records whose source text came from Slack are shown

  Rule: The history detail links to the entries saved from that record
    Scenario: See which words were saved
      Given the user saved "follow up" and "bandwidth" from one record
      When the user opens that record's detail
      Then the detail lists these two entries
      And choosing either entry opens it in the notebook

    Scenario: The links shrink after an entry is deleted
      Given the user saved "follow up" and "bandwidth" from one record
      When the user deletes "bandwidth" in the notebook
      Then the record's detail lists only "follow up"

    Scenario: Deleting history does not affect entries
      Given the user saved "follow up" from one record
      When the user deletes that record
      Then "follow up" and its context are still in the notebook
