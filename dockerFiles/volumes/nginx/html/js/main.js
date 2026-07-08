// 主 JavaScript 文件
document.addEventListener('DOMContentLoaded', function() {
    // 更新服务器时间
    updateServerTime();
    setInterval(updateServerTime, 1000);
    
    // 平滑滚动导航
    setupSmoothScrolling();
    
    // 导航栏滚动效果
    setupNavbarScrollEffect();
    
    // 健康检查功能
    setupHealthCheck();
});

// 更新服务器时间显示
function updateServerTime() {
    const timeElement = document.getElementById('server-time');
    if (timeElement) {
        const now = new Date();
        const timeString = now.toLocaleString('zh-CN', {
            year: 'numeric',
            month: '2-digit',
            day: '2-digit',
            hour: '2-digit',
            minute: '2-digit',
            second: '2-digit'
        });
        timeElement.textContent = timeString;
    }
}

// 设置平滑滚动导航
function setupSmoothScrolling() {
    const navLinks = document.querySelectorAll('.nav-menu a[href^="#"]');
    
    navLinks.forEach(link => {
        link.addEventListener('click', function(e) {
            e.preventDefault();
            
            const targetId = this.getAttribute('href').substring(1);
            const targetElement = document.getElementById(targetId);
            
            if (targetElement) {
                const headerHeight = document.querySelector('.header').offsetHeight;
                const targetPosition = targetElement.offsetTop - headerHeight - 20;
                
                window.scrollTo({
                    top: targetPosition,
                    behavior: 'smooth'
                });
            }
        });
    });
}

// 导航栏滚动效果
function setupNavbarScrollEffect() {
    const header = document.querySelector('.header');
    let lastScrollTop = 0;
    
    window.addEventListener('scroll', function() {
        const scrollTop = window.pageYOffset || document.documentElement.scrollTop;
        
        if (scrollTop > lastScrollTop && scrollTop > 100) {
            // 向下滚动，隐藏导航栏
            header.style.transform = 'translateY(-100%)';
        } else {
            // 向上滚动，显示导航栏
            header.style.transform = 'translateY(0)';
        }
        
        // 添加背景透明度效果
        if (scrollTop > 50) {
            header.style.background = 'rgba(255, 255, 255, 0.15)';
        } else {
            header.style.background = 'rgba(255, 255, 255, 0.1)';
        }
        
        lastScrollTop = scrollTop;
    });
}

// 健康检查功能
function setupHealthCheck() {
    const healthButton = document.querySelector('a[href="/health"]');
    
    if (healthButton) {
        healthButton.addEventListener('click', function(e) {
            e.preventDefault();
            checkHealth();
        });
    }
    
    // 页面加载时自动检查一次
    setTimeout(checkHealth, 1000);
}

// 执行健康检查
async function checkHealth() {
    try {
        const response = await fetch('/health');
        const statusElements = document.querySelectorAll('.status-value.online');
        
        if (response.ok) {
            statusElements.forEach(element => {
                element.textContent = '在线';
                element.className = 'status-value online';
            });
            
            // 更新状态徽章
            const statusBadge = document.querySelector('.status-badge');
            if (statusBadge) {
                statusBadge.style.background = 'rgba(76, 175, 80, 0.8)';
                statusBadge.querySelector('.status-text').textContent = '服务运行正常';
                statusBadge.querySelector('.status-icon').textContent = '✅';
            }
            
            showNotification('健康检查通过', 'success');
        } else {
            throw new Error('Health check failed');
        }
    } catch (error) {
        console.error('Health check error:', error);
        
        const statusElements = document.querySelectorAll('.status-value.online');
        statusElements.forEach(element => {
            element.textContent = '离线';
            element.className = 'status-value offline';
        });
        
        // 更新状态徽章
        const statusBadge = document.querySelector('.status-badge');
        if (statusBadge) {
            statusBadge.style.background = 'rgba(244, 67, 54, 0.8)';
            statusBadge.querySelector('.status-text').textContent = '服务异常';
            statusBadge.querySelector('.status-icon').textContent = '❌';
        }
        
        showNotification('健康检查失败', 'error');
    }
}

// 显示通知
function showNotification(message, type = 'info') {
    // 创建通知元素
    const notification = document.createElement('div');
    notification.className = `notification notification-${type}`;
    notification.textContent = message;
    
    // 添加样式
    Object.assign(notification.style, {
        position: 'fixed',
        top: '100px',
        right: '20px',
        padding: '1rem 2rem',
        borderRadius: '5px',
        color: 'white',
        fontWeight: '600',
        zIndex: '9999',
        transform: 'translateX(100%)',
        transition: 'transform 0.3s ease',
        maxWidth: '300px',
        wordWrap: 'break-word'
    });
    
    // 设置背景颜色
    switch (type) {
        case 'success':
            notification.style.background = '#28a745';
            break;
        case 'error':
            notification.style.background = '#dc3545';
            break;
        case 'warning':
            notification.style.background = '#ffc107';
            notification.style.color = '#333';
            break;
        default:
            notification.style.background = '#17a2b8';
    }
    
    // 添加到页面
    document.body.appendChild(notification);
    
    // 显示动画
    setTimeout(() => {
        notification.style.transform = 'translateX(0)';
    }, 100);
    
    // 自动隐藏
    setTimeout(() => {
        notification.style.transform = 'translateX(100%)';
        setTimeout(() => {
            if (notification.parentNode) {
                notification.parentNode.removeChild(notification);
            }
        }, 300);
    }, 3000);
}

// 添加一些实用的工具函数
const utils = {
    // 格式化文件大小
    formatFileSize: function(bytes) {
        if (bytes === 0) return '0 Bytes';
        const k = 1024;
        const sizes = ['Bytes', 'KB', 'MB', 'GB'];
        const i = Math.floor(Math.log(bytes) / Math.log(k));
        return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
    },
    
    // 格式化时间差
    formatTimeDiff: function(timestamp) {
        const now = Date.now();
        const diff = now - timestamp;
        const seconds = Math.floor(diff / 1000);
        const minutes = Math.floor(seconds / 60);
        const hours = Math.floor(minutes / 60);
        const days = Math.floor(hours / 24);
        
        if (days > 0) return `${days}天前`;
        if (hours > 0) return `${hours}小时前`;
        if (minutes > 0) return `${minutes}分钟前`;
        return `${seconds}秒前`;
    },
    
    // 复制到剪贴板
    copyToClipboard: function(text) {
        if (navigator.clipboard) {
            navigator.clipboard.writeText(text).then(() => {
                showNotification('已复制到剪贴板', 'success');
            });
        } else {
            // 兼容旧浏览器
            const textArea = document.createElement('textarea');
            textArea.value = text;
            document.body.appendChild(textArea);
            textArea.select();
            document.execCommand('copy');
            document.body.removeChild(textArea);
            showNotification('已复制到剪贴板', 'success');
        }
    }
};

// 将工具函数暴露到全局
window.utils = utils;