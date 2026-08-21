#import "ConfigViewController.h"
#import "SpoofManager.h"
#import <spawn.h>

@interface ConfigViewController ()
@property (nonatomic, strong) NSArray *sortedKeys;
@property (nonatomic, strong) NSDictionary *models;
@property (nonatomic, strong) NSString *currentModel;
@end

@implementation ConfigViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"DeviceSpoofPro";
    self.tableView.tableFooterView = [UIView new];

    SpoofManager *mgr = [SpoofManager sharedManager];
    [mgr loadConfig];
    self.models = [mgr allSupportedModels];
    self.currentModel = [mgr currentConfig].modelIdentifier;

    // 按型号 Key 排序
    self.sortedKeys = [self.models.allKeys sortedArrayUsingSelector:@selector(compare:)];

    // 导航栏右侧刷新按钮
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(restartAlert)];
}

#pragma mark - Table View

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 1; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    return self.sortedKeys.count;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellId = @"ModelCell";
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellId];
    }

    NSString *key = self.sortedKeys[indexPath.row];
    NSDictionary *info = self.models[key];

    cell.textLabel.text = info[@"name"];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@  %@  %@", key, info[@"chip"], info[@"release"]];

    if ([key isEqualToString:self.currentModel]) {
        cell.accessoryType = UITableViewCellAccessoryCheckmark;
    } else {
        cell.accessoryType = UITableViewCellAccessoryNone;
    }

    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tv deselectRowAtIndexPath:indexPath animated:YES];

    NSString *key = self.sortedKeys[indexPath.row];
    SpoofManager *mgr = [SpoofManager sharedManager];

    if ([mgr switchToModel:key]) {
        if ([mgr saveConfig]) {
            self.currentModel = key;
            [self.tableView reloadData];
            [self showRestartAlert];
        } else {
            [self showAlert:@"保存失败" message:@"无法写入配置文件，请检查权限"];
        }
    }
}

#pragma mark - 重启

- (void)restartAlert {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"重启生效"
                                                                     message:@"切换型号后需要重启 SpringBoard 才能生效，现在重启吗？"
                                                              preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"稍后" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"立即重启" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        [self restartSpringBoard];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showRestartAlert {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"切换成功"
                                                                     message:@"已切换设备型号，重启 SpringBoard 后生效"
                                                              preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"稍后重启" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"立即重启" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        [self restartSpringBoard];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)restartSpringBoard {
    // 通过 posix_spawn 重启 SpringBoard（system() 在 iOS 上不可用）
    pid_t pid = 0;
    char *argv[] = {"killall", "-9", "SpringBoard", NULL};
    char *envp[] = {NULL};
    posix_spawn(&pid, "/usr/bin/killall", NULL, NULL, argv, envp);
    if (pid > 0) {
        int status = 0;
        waitpid(pid, &status, 0);
    }
}

- (void)showAlert:(NSString *)title message:(NSString *)msg {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
