/**
 * This class contains unit tests for validating the behavior of Apex classes
 * and triggers.
 *
 * Unit tests are class methods that verify whether a particular piece
 * of code is working properly. Unit test methods take no arguments,
 * commit no data to the database, and are flagged with the testMethod
 * keyword in the method definition.
 *
 * All test methods in an org are executed whenever Apex code is deployed
 * to a production org to confirm correctness, ensure code
 * coverage, and prevent regressions. All Apex classes are
 * required to have at least 75% code coverage in order to be deployed
 * to a production org. In addition, all triggers must have some code coverage.
 * 
 * The @isTest class annotation indicates this class only contains test
 * methods. Classes defined with the @isTest annotation do not count against
 * the org size limit for all Apex scripts.
 *
 * See the Apex Language Reference for more information about Testing and Code Coverage.
 */
@IsTest
private class ConfigServiceTest {

    @IsTest
    static void testConfigValues() {
        Test.startTest();

        System.assertEquals(24, ConfigService.getCacheRefreshHours());
        System.assertEquals(30, ConfigService.getMaxAuditTrailDays());
        System.assertEquals(true, ConfigService.isTriggerAnalysisEnabled());
        System.assertEquals(true, ConfigService.isFlowAnalysisEnabled());
        System.assertEquals(50, ConfigService.getMaxResultsDisplay());
        System.assertEquals(30, ConfigService.getApiTimeoutSeconds());
        System.assertEquals(false, ConfigService.isDebugLoggingEnabled());

        Test.stopTest();
    }
}